#!/usr/bin/env bash
#
# Load YouBike snapshot CSVs from data/youbike_Taipei/ and data/youbike_NewTaipei/
# into the `youbike_snapshots` table of the hackathon DB.
#
# Idempotent: a unique index on (station_uid, snapshot_at) makes re-runs skip
# rows that were already inserted, so this is safe to run repeatedly as new
# CSVs land in data/.
#
# Env overrides:
#   PG_CONTAINER  (default: postgres-manager)
#   PG_USER       (default: postgres)
#   PG_DB         (default: hackathon)
#   DATA_DIR      (default: <repo>/data)
#   DOCKER        (default: "sudo docker"; set to "docker" if rootless)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${DATA_DIR:-${REPO_ROOT}/data}"

PG_CONTAINER="${PG_CONTAINER:-postgres-manager}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-hackathon}"
DOCKER="${DOCKER:-sudo docker}"

psql_run() {
    ${DOCKER} exec -i "${PG_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${PG_DB}" "$@"
}

echo "==> Ensuring unique index on youbike_snapshots(station_uid, snapshot_at)"
psql_run -q -c "CREATE UNIQUE INDEX IF NOT EXISTS uq_youbike_snapshots_station_time ON youbike_snapshots(station_uid, snapshot_at);"

shopt -s nullglob
files=( "${DATA_DIR}"/youbike_Taipei/*.csv "${DATA_DIR}"/youbike_NewTaipei/*.csv )

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No CSV files found under ${DATA_DIR}/youbike_{Taipei,NewTaipei}" >&2
    exit 1
fi

total_before="$(psql_run -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
echo "==> Loading ${#files[@]} CSV files into ${PG_DB} (current rows: ${total_before})"

load_one() {
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
    } | psql_run -q
}

for csv in "${files[@]}"; do
    load_one "${csv}"
    printf '    %s\n' "$(basename "${csv}")"
done

total_after_csv="$(psql_run -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
inserted_from_csv=$(( total_after_csv - total_before ))

echo "==> Filling missing (city, hour, quarter) slots from random same-city snapshots"
psql_run -q < "${REPO_ROOT}/scripts/fill-missing-youbike-slots.sql"

total_after="$(psql_run -tA -c 'SELECT COUNT(*) FROM youbike_snapshots;')"
inserted_filled=$(( total_after - total_after_csv ))

echo
echo "==> Done. Rows: ${total_before} -> ${total_after} (+${inserted_from_csv} from CSVs, +${inserted_filled} from gap-fill)"
psql_run -c "
SELECT
    city,
    COUNT(*)                       AS rows,
    COUNT(DISTINCT station_uid)    AS stations,
    COUNT(DISTINCT date_trunc('hour', snapshot_at AT TIME ZONE 'Asia/Taipei')) AS hour_buckets,
    MIN(snapshot_at)               AS first_snapshot,
    MAX(snapshot_at)               AS last_snapshot
FROM youbike_snapshots
GROUP BY city
ORDER BY city;
"
