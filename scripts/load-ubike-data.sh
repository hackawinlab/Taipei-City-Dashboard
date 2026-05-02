#!/usr/bin/env bash
#
# load-ubike-data.sh — one-shot YouBike database initialization.
#
# Bootstraps everything needed for the YouBike time-series feature:
#   1. Creates the hackathon DB (if missing).
#   2. Seeds dashboardmanager: timemap component + "Youbike Analysis" dashboard.
#   3. Initializes the youbike_snapshots schema and indexes.
#   4. Loads real CSV snapshots from ${DATA_DIR}/youbike_{Taipei,NewTaipei}/*.csv.
#   5. Fills missing 15-min slots so the time slider has data at every quarter.
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
#   PG_CONTAINER  (default: postgres-manager)
#   PG_USER       (default: postgres)
#   HACKATHON_DB  (default: hackathon)
#   MANAGER_DB    (default: dashboardmanager)
#   DATA_DIR      (default: <repo>/data — CSVs are NOT committed; place them here)
#   DOCKER        (default: "sudo docker"; set to "docker" for rootless)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PG_CONTAINER="${PG_CONTAINER:-postgres-manager}"
PG_USER="${PG_USER:-postgres}"
HACKATHON_DB="${HACKATHON_DB:-hackathon}"
MANAGER_DB="${MANAGER_DB:-dashboardmanager}"
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

# ---------- 1. Ensure hackathon DB exists ----------
echo "==> [1/5] Ensuring '${HACKATHON_DB}' database exists"
db_exists="$(psql_root -tA -c "SELECT 1 FROM pg_database WHERE datname='${HACKATHON_DB}'")"
if [[ -z "${db_exists}" ]]; then
    psql_root -c "CREATE DATABASE ${HACKATHON_DB};"
    echo "    Created."
else
    echo "    Exists — skipping create."
fi

# ---------- 2. Seed dashboardmanager (component + dashboard) ----------
echo "==> [2/5] Seeding ${MANAGER_DB} (timemap + shortage blocks + Youbike Analysis dashboard)"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-timemap-seed.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-analysis-dashboard.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-shortage-blocks-seed.sql"

# ---------- 3. Initialize hackathon schema ----------
echo "==> [3/5] Initializing ${HACKATHON_DB} schema (table + indexes)"
psql_db "${HACKATHON_DB}" -q <<'SQL'
CREATE TABLE IF NOT EXISTS youbike_snapshots (
  id              BIGSERIAL PRIMARY KEY,
  station_uid     VARCHAR(50)       NOT NULL,
  station_name    VARCHAR(100)      NOT NULL,
  lat             DOUBLE PRECISION  NOT NULL,
  lon             DOUBLE PRECISION  NOT NULL,
  city            VARCHAR(20)       NOT NULL,
  available_bikes INT               NOT NULL DEFAULT 0,
  electric_bikes  INT               NOT NULL DEFAULT 0,
  total_docks     INT               NOT NULL DEFAULT 0,
  snapshot_at     TIMESTAMPTZ       NOT NULL
);
ALTER TABLE youbike_snapshots ADD COLUMN IF NOT EXISTS electric_bikes INT NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS uq_youbike_snapshots_station_time
    ON youbike_snapshots(station_uid, snapshot_at);
CREATE INDEX IF NOT EXISTS idx_youbike_hour ON youbike_snapshots
    (city, (EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')));
SQL

# ---------- 4. Load CSVs (preferred) or mock data (fallback) ----------
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
    available_bikes, electric_bikes, total_docks, snapshot_at
)
SELECT
    station_uid, station_name, lat, lon, city,
    available_bikes, COALESCE(electric_bikes, 0), total_docks, snapshot_at
FROM _stg_youbike
ON CONFLICT (station_uid, snapshot_at) DO UPDATE
    SET electric_bikes = EXCLUDED.electric_bikes;
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

echo "==> [4/5] Loading ${#csv_files[@]} CSV files from ${DATA_DIR}"
rows_before="$(psql_db "${HACKATHON_DB}" -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
for csv in "${csv_files[@]}"; do
    load_one_csv "${csv}"
    printf '      %s\n' "$(basename "${csv}")"
done
rows_after="$(psql_db "${HACKATHON_DB}" -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
echo "    Inserted $((rows_after - rows_before)) new rows (existing rows: ${rows_before})."

# ---------- 5. Fill missing 15-min slots ----------
echo "==> [5/5] Filling missing (city × hour × quarter) slots so every slider tick has data"
psql_db "${HACKATHON_DB}" -q < "${REPO_ROOT}/scripts/fill-missing-youbike-slots.sql"

# ---------- Summary ----------
echo
echo "==> Done. Coverage summary:"
psql_db "${HACKATHON_DB}" -c "
SELECT
    city,
    COUNT(*)                       AS rows,
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
