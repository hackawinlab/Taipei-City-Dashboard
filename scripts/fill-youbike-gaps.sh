#!/usr/bin/env bash
#
# Normalize youbike_snapshots so every distinct snapshot lands on a 15-min
# slider slot anchor (HH:00, HH:15, HH:30, HH:45).
#
# Steps:
#   1. Delete legacy mock-seed rows (station_uid LIKE 'TPE0%' / 'NTP0%').
#   2. Delete any synthetic rows left over from a previous run of an older
#      version of this script (date == SYNTHETIC_DATE_LEGACY).
#   3. Ensure helper indexes.
#   4. Fill (station × snapshot_at) gaps within each city by copying values
#      from the same station's nearest-in-time snapshot — safety for cases
#      where a station is missing from some snapshot.
#   5. Rewrite snapshot_at on existing rows: per (city, hour) group, the
#      i-th distinct snapshot in chronological order is moved to
#      HH:(i*15):00 Asia/Taipei. Hours with 1..4 distinct snapshots end up
#      cleanly mapped to quarters 0..3. Snapshots beyond the 4th in any
#      hour are dropped (none today).
#
# After the swap, every row in the table sits on one of the 96 slider
# positions, and every station has data at every slot that the city had
# real data for.
#
# Idempotent — safe to re-run after loading new CSVs via load-youbike-csv.sh.
#
# Env overrides: PG_CONTAINER, PG_USER, PG_DB, DOCKER.

set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-postgres-manager}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-hackathon}"
DOCKER="${DOCKER:-sudo docker}"
SYNTHETIC_DATE_LEGACY="${SYNTHETIC_DATE_LEGACY:-2026-05-03}"

psql_run() {
    ${DOCKER} exec -i "${PG_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${PG_DB}" "$@"
}

echo "==> Removing legacy mock-seed rows (TPE0%/NTP0% station_uid)"
psql_run -c "DELETE FROM youbike_snapshots WHERE station_uid LIKE 'TPE0%' OR station_uid LIKE 'NTP0%';"

echo "==> Removing any synthetic rows from prior script versions (date=${SYNTHETIC_DATE_LEGACY})"
psql_run -c "
DELETE FROM youbike_snapshots
WHERE (snapshot_at AT TIME ZONE 'Asia/Taipei')::date = '${SYNTHETIC_DATE_LEGACY}';
"

echo "==> Ensuring helper indexes"
psql_run -q -c "
CREATE UNIQUE INDEX IF NOT EXISTS uq_youbike_snapshots_station_time
    ON youbike_snapshots(station_uid, snapshot_at);
CREATE INDEX IF NOT EXISTS idx_youbike_snapshots_city_time
    ON youbike_snapshots(city, snapshot_at);
"

echo "==> Filling per-station gaps via nearest-in-time copy (safety pass)"
psql_run <<'SQL'
WITH
station_meta AS (
    SELECT DISTINCT ON (station_uid) station_uid, station_name, lat, lon, city
    FROM youbike_snapshots
    ORDER BY station_uid, snapshot_at DESC
),
city_times AS (SELECT DISTINCT city, snapshot_at FROM youbike_snapshots),
grid AS (
    SELECT s.station_uid, s.station_name, s.lat, s.lon, s.city, t.snapshot_at
    FROM station_meta s JOIN city_times t USING (city)
)
INSERT INTO youbike_snapshots (
    station_uid, station_name, lat, lon, city,
    available_bikes, total_docks, snapshot_at
)
SELECT
    g.station_uid, g.station_name, g.lat, g.lon, g.city,
    nearest.available_bikes, nearest.total_docks, g.snapshot_at
FROM grid g
LEFT JOIN youbike_snapshots e
    ON e.station_uid = g.station_uid AND e.snapshot_at = g.snapshot_at
JOIN LATERAL (
    SELECT y.available_bikes, y.total_docks
    FROM youbike_snapshots y
    WHERE y.station_uid = g.station_uid
    ORDER BY ABS(EXTRACT(EPOCH FROM (y.snapshot_at - g.snapshot_at)))
    LIMIT 1
) nearest ON TRUE
WHERE e.station_uid IS NULL
ON CONFLICT (station_uid, snapshot_at) DO NOTHING;
SQL

echo "==> Rewriting snapshot_at to land on 15-min slot anchors"
echo "    (drop unique index, UPDATE, recreate to re-validate)"
psql_run <<'SQL'
BEGIN;

DROP INDEX IF EXISTS uq_youbike_snapshots_station_time;

WITH
src AS (SELECT DISTINCT city, snapshot_at FROM youbike_snapshots),
ranked AS (
    SELECT
        city,
        snapshot_at AS old_at,
        EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int AS hour,
        ROW_NUMBER() OVER (
            PARTITION BY city,
                         EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')
            ORDER BY snapshot_at
        ) - 1 AS quarter
    FROM src
),
-- Drop rows for any 5th+ snapshot in an hour (none today; defensive).
overflow_delete AS (
    DELETE FROM youbike_snapshots y
    USING ranked r
    WHERE y.snapshot_at = r.old_at AND y.city = r.city AND r.quarter > 3
    RETURNING 1
),
remap AS (
    UPDATE youbike_snapshots y
    SET snapshot_at =
        ((y.snapshot_at AT TIME ZONE 'Asia/Taipei')::date::timestamp
         + (r.hour || ' hours')::interval
         + (r.quarter * 15 || ' minutes')::interval
        ) AT TIME ZONE 'Asia/Taipei'
    FROM ranked r
    WHERE y.snapshot_at = r.old_at AND y.city = r.city AND r.quarter <= 3
    RETURNING 1
)
SELECT
    (SELECT COUNT(*) FROM remap)            AS rows_remapped,
    (SELECT COUNT(*) FROM overflow_delete)  AS rows_dropped_overflow;

CREATE UNIQUE INDEX uq_youbike_snapshots_station_time
    ON youbike_snapshots(station_uid, snapshot_at);

COMMIT;
SQL

echo
echo "==> Coverage verification (per city)"
psql_run -c "
WITH
city_stations AS (SELECT city, COUNT(DISTINCT station_uid) AS n FROM youbike_snapshots GROUP BY city),
slot_count    AS (
    SELECT city,
           COUNT(DISTINCT (
               EXTRACT(HOUR   FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int * 4 +
               EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int / 15
           )) AS slots_populated_of_96
    FROM youbike_snapshots
    GROUP BY city
),
actual        AS (SELECT city, COUNT(*) AS rows FROM youbike_snapshots GROUP BY city)
SELECT a.city,
       cs.n              AS stations,
       sc.slots_populated_of_96,
       a.rows
FROM actual a
JOIN city_stations cs USING (city)
JOIN slot_count    sc USING (city)
ORDER BY city;

-- Show the new slot layout per hour, per city
SELECT
    city,
    EXTRACT(HOUR   FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int   AS hour,
    array_agg(DISTINCT EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int ORDER BY EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int) AS minute_slots
FROM youbike_snapshots
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 25;
"
