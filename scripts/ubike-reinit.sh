#!/usr/bin/env bash
#
# ubike-reinit.sh — wipe the YouBike dataset and reload from CSVs.
#
# Drops the hackathon database (where youbike_snapshots lives), then runs
# load-ubike-data.sh to recreate the schema with the latest columns,
# re-seed the dashboardmanager component, reload every CSV in data/, and
# gap-fill missing 15-min slots.
#
# Use this when:
#   - The schema changed (new column, renamed column) and you want a clean
#     slate without ALTER TABLE migrations
#   - Stale gap-fill rows need to be flushed and regenerated
#   - You're switching to a different CSV snapshot set
#
# Stop the backend first if it's running — it holds a connection to the
# hackathon DB that would block DROP DATABASE. The script forcibly
# terminates any leftover connections before dropping.
#
# Usage:
#   ./scripts/ubike-reinit.sh
#
# Env overrides (match load-ubike-data.sh):
#   PG_CONTAINER  (default: postgres-manager)
#   PG_USER       (default: postgres)
#   HACKATHON_DB  (default: hackathon)
#   DOCKER        (default: "sudo docker"; set to "docker" for rootless)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PG_CONTAINER="${PG_CONTAINER:-postgres-manager}"
PG_USER="${PG_USER:-postgres}"
HACKATHON_DB="${HACKATHON_DB:-hackathon}"
DOCKER="${DOCKER:-sudo docker}"

psql_root() {
    ${DOCKER} exec -i "${PG_CONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PG_USER}" "$@"
}

echo "==> Terminating connections to '${HACKATHON_DB}' (if any)"
psql_root -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${HACKATHON_DB}' AND pid <> pg_backend_pid();" >/dev/null

echo "==> Dropping '${HACKATHON_DB}' database (if it exists)"
psql_root -c "DROP DATABASE IF EXISTS ${HACKATHON_DB};"

echo "==> Re-running load-ubike-data.sh"
exec "${REPO_ROOT}/scripts/load-ubike-data.sh"
