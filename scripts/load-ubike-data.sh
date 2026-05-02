#!/usr/bin/env bash
#
# load-ubike-data.sh — one-shot YouBike database initialization.
#
# Bootstraps everything needed for the YouBike time-series feature:
#   1. Creates the hackathon DB (if missing).
#   2. Seeds dashboardmanager: timemap component + "Youbike Analysis" dashboard.
#   3. Initializes the youbike_snapshots schema and indexes.
#   4. Loads real CSV snapshots from ${DATA_DIR}/youbike_{Taipei,NewTaipei}/*.csv
#      into youbike_snapshots (history, used by the timemap slider).
#   5. Fills missing 15-min slots so the time slider has data at every quarter.
#   6. Refreshes tran_ubike_realtime / tran_ubike_realtime_new_tpe from the
#      latest CSV snapshot per station (one-shot, used by the existing
#      youbike_availability donut on the dashboard tab).
#
# Idempotent — safe to re-run after pulling fresh CSVs. Real CSVs are required;
# for a quick demo, drop a handful of CSVs from the pipeline host into
# data/youbike_{Taipei,NewTaipei}/ and re-run — the gap-fill step will project
# whatever you load across all 96 quarter-hour slots.
#
# Usage:
#   ./scripts/load-ubike-data.sh
#
# Env overrides:
#   PG_CONTAINER       (default: postgres-manager — hosts hackathon + dashboardmanager DBs)
#   PG_DATA_CONTAINER  (default: postgres-data    — hosts dashboard DB w/ tran_ubike_realtime)
#   PG_USER            (default: postgres)
#   HACKATHON_DB       (default: hackathon)
#   MANAGER_DB         (default: dashboardmanager)
#   DASHBOARD_DB       (default: dashboard)
#   DATA_DIR           (default: <repo>/data — CSVs are NOT committed; place them here)
#   DOCKER             (default: "sudo docker"; set to "docker" for rootless)
#   SKIP_REALTIME=1    skip the step-6 refresh of tran_ubike_realtime tables

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PG_CONTAINER="${PG_CONTAINER:-postgres-manager}"
PG_DATA_CONTAINER="${PG_DATA_CONTAINER:-postgres-data}"
PG_USER="${PG_USER:-postgres}"
HACKATHON_DB="${HACKATHON_DB:-hackathon}"
MANAGER_DB="${MANAGER_DB:-dashboardmanager}"
DASHBOARD_DB="${DASHBOARD_DB:-dashboard}"
DATA_DIR="${DATA_DIR:-${REPO_ROOT}/data}"
DOCKER="${DOCKER:-sudo docker}"

psql_root() {
    ${DOCKER} exec -i "${PG_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" "$@"
}

psql_db() {
    local db="$1"; shift
    ${DOCKER} exec -i "${PG_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${db}" "$@"
}

psql_data_db() {
    local db="$1"; shift
    ${DOCKER} exec -i "${PG_DATA_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${db}" "$@"
}

# ---------- 1. Ensure hackathon DB exists ----------
echo "==> [1/6] Ensuring '${HACKATHON_DB}' database exists"
db_exists="$(psql_root -tA -c "SELECT 1 FROM pg_database WHERE datname='${HACKATHON_DB}'")"
if [[ -z "${db_exists}" ]]; then
    psql_root -c "CREATE DATABASE ${HACKATHON_DB};"
    echo "    Created."
else
    echo "    Exists — skipping create."
fi

# ---------- 2. Seed dashboardmanager (component + dashboard) ----------
echo "==> [2/6] Seeding ${MANAGER_DB} (timemap component + Youbike Analysis dashboard)"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-timemap-seed.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-analysis-dashboard.sql"

# ---------- 3. Initialize hackathon schema ----------
echo "==> [3/6] Initializing ${HACKATHON_DB} schema (table + indexes)"
psql_db "${HACKATHON_DB}" -q <<'SQL'
CREATE TABLE IF NOT EXISTS youbike_snapshots (
  id              BIGSERIAL PRIMARY KEY,
  station_uid     VARCHAR(50)       NOT NULL,
  station_name    VARCHAR(100)      NOT NULL,
  lat             DOUBLE PRECISION  NOT NULL,
  lon             DOUBLE PRECISION  NOT NULL,
  city            VARCHAR(20)       NOT NULL,
  available_bikes INT               NOT NULL DEFAULT 0,
  total_docks     INT               NOT NULL DEFAULT 0,
  snapshot_at     TIMESTAMPTZ       NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_youbike_snapshots_station_time
    ON youbike_snapshots(station_uid, snapshot_at);
CREATE INDEX IF NOT EXISTS idx_youbike_hour ON youbike_snapshots
    (city, (EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')));
SQL

# ---------- 4. Load CSVs into youbike_snapshots ----------
load_one_csv() {
    local csv="$1"
    {
        cat <<'SQL'
BEGIN;
CREATE TEMP TABLE _stg_youbike (
    snapshot_at      timestamptz,
    city             varchar(20),
    station_uid      varchar(50),
    station_name     varchar(100),
    lat              double precision,
    lon              double precision,
    available_bikes  integer,
    available_docks  integer,
    total_docks      integer,
    electric_bikes   integer
) ON COMMIT DROP;
\COPY _stg_youbike FROM STDIN WITH (FORMAT csv, HEADER true)
SQL
        cat "${csv}"
        printf '\\.\n'
        cat <<'SQL'
INSERT INTO youbike_snapshots (
    station_uid, station_name, lat, lon, city,
    available_bikes, total_docks, snapshot_at
)
SELECT
    station_uid, station_name, lat, lon, city,
    available_bikes, total_docks, snapshot_at
FROM _stg_youbike
ON CONFLICT (station_uid, snapshot_at) DO NOTHING;
COMMIT;
SQL
    } | psql_db "${HACKATHON_DB}" -q
}

shopt -s nullglob
csv_files=( "${DATA_DIR}"/youbike_Taipei/*.csv "${DATA_DIR}"/youbike_NewTaipei/*.csv )
shopt -u nullglob

if [[ ${#csv_files[@]} -eq 0 ]]; then
    echo "ERROR: no CSVs under ${DATA_DIR}/youbike_{Taipei,NewTaipei}." >&2
    echo "       Pull real snapshots from the pipeline host, e.g.:" >&2
    echo "         rsync -ah winlab@192.168.10.71:hackathon-pipeline/data/youbike_Taipei    data/" >&2
    echo "         rsync -ah winlab@192.168.10.71:hackathon-pipeline/data/youbike_NewTaipei data/" >&2
    echo "       For a quick demo, copy any few CSVs into those subdirs — gap-fill will" >&2
    echo "       project them across all 96 quarter-hour slots." >&2
    exit 1
fi

echo "==> [4/6] Loading ${#csv_files[@]} CSV files from ${DATA_DIR}"
rows_before="$(psql_db "${HACKATHON_DB}" -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
for csv in "${csv_files[@]}"; do
    load_one_csv "${csv}"
    printf '      %s\n' "$(basename "${csv}")"
done
rows_after="$(psql_db "${HACKATHON_DB}" -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
echo "    Inserted $((rows_after - rows_before)) new rows (existing rows: ${rows_before})."

# ---------- 5. Fill missing 15-min slots ----------
echo "==> [5/6] Filling missing (city × hour × quarter) slots so every slider tick has data"
psql_db "${HACKATHON_DB}" -q < "${REPO_ROOT}/scripts/fill-missing-youbike-slots.sql"

# ---------- 6. Refresh tran_ubike_realtime (one-shot current state) ----------
# The youbike_availability donut on the "Youbike Analysis" dashboard reads from
# tran_ubike_realtime + tran_ubike_realtime_new_tpe in the dashboard DB.
# These get seeded with stale 2024 demo data by dashboard-demo.sql; replace
# them with the latest snapshot per station from our CSVs so the donut
# reflects the same dataset as the timemap slider.
if [[ "${SKIP_REALTIME:-0}" == "1" ]]; then
    echo "==> [6/6] SKIP_REALTIME=1 — leaving tran_ubike_realtime tables untouched."
else
    echo "==> [6/6] Refreshing tran_ubike_realtime / tran_ubike_realtime_new_tpe (latest snapshot per station)"
    {
        cat <<'SQL'
BEGIN;
CREATE TEMP TABLE _stg_realtime (
    snapshot_at      timestamptz,
    city             varchar(20),
    station_uid      varchar(50),
    station_name     varchar(100),
    lat              double precision,
    lon              double precision,
    available_bikes  integer,
    available_docks  integer,
    total_docks      integer,
    electric_bikes   integer
) ON COMMIT DROP;
SQL
        for csv in "${csv_files[@]}"; do
            printf '\\COPY _stg_realtime FROM STDIN WITH (FORMAT csv, HEADER true)\n'
            cat "${csv}"
            printf '\\.\n'
        done
        cat <<'SQL'
TRUNCATE tran_ubike_realtime;
INSERT INTO tran_ubike_realtime (
    data_time, station_uid, station_id, service_status, service_type,
    available_rent_general_bikes, available_return_bikes, available_rent_electric_bikes,
    tdx_update_time
)
SELECT DISTINCT ON (station_uid)
    snapshot_at, station_uid, station_uid, '1', '2',
    GREATEST(available_bikes - COALESCE(electric_bikes, 0), 0),
    available_docks,
    COALESCE(electric_bikes, 0),
    snapshot_at
FROM _stg_realtime
WHERE city = 'Taipei'
ORDER BY station_uid, snapshot_at DESC;

TRUNCATE tran_ubike_realtime_new_tpe;
INSERT INTO tran_ubike_realtime_new_tpe (
    data_time, station_uid, station_id, service_status, service_type,
    available_rent_general_bikes, available_return_bikes, available_rent_electric_bikes,
    tdx_update_time
)
SELECT DISTINCT ON (station_uid)
    snapshot_at, station_uid, station_uid, '1', '2',
    GREATEST(available_bikes - COALESCE(electric_bikes, 0), 0),
    available_docks,
    COALESCE(electric_bikes, 0),
    snapshot_at
FROM _stg_realtime
WHERE city = 'NewTaipei'
ORDER BY station_uid, snapshot_at DESC;
COMMIT;
SQL
    } | psql_data_db "${DASHBOARD_DB}" -q
fi

# ---------- Summary ----------
echo
echo "==> Done. Coverage summary:"
psql_db "${HACKATHON_DB}" -c "
SELECT
    city,
    COUNT(*)                       AS history_rows,
    COUNT(DISTINCT station_uid)    AS stations,
    COUNT(DISTINCT (
        EXTRACT(HOUR   FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int * 4 +
        EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int / 15
    )) AS slots_of_96,
    MIN(snapshot_at)               AS first_snapshot,
    MAX(snapshot_at)               AS last_snapshot
FROM youbike_snapshots
GROUP BY city
ORDER BY city;
"
if [[ "${SKIP_REALTIME:-0}" != "1" ]]; then
    psql_data_db "${DASHBOARD_DB}" -c "
    SELECT 'Taipei'    AS city, COUNT(*) AS realtime_rows, MAX(data_time) AS last_data_time FROM tran_ubike_realtime
    UNION ALL
    SELECT 'NewTaipei' AS city, COUNT(*) AS realtime_rows, MAX(data_time) AS last_data_time FROM tran_ubike_realtime_new_tpe
    ORDER BY city;
    "
fi
