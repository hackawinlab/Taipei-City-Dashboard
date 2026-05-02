# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Taipei City Dashboard is a geospatial data visualization platform with three independently deployable subsystems:

- `Taipei-City-Dashboard-FE/` — Vue 3 SPA (Vite, Pinia, Mapbox GL, deck.gl)
- `Taipei-City-Dashboard-BE/` — Go REST API (Gin, GORM, PostGIS, Redis, Qdrant, ONNX)
- `Taipei-City-Dashboard-DE/` — Airflow ETL pipelines (Python, Celery, custom operators)

---

## Local Development Environment

This section describes how the repo is actually run on this machine (non-Docker backend + Docker DBs).

### Prerequisites (one-time)

Ubuntu ships with system `postgresql` (port 5432) and `redis-server` (port 6379) that conflict with Docker containers. Disable them permanently:

```bash
sudo systemctl stop postgresql redis-server
sudo systemctl disable postgresql redis-server
```

Create the Docker bridge network once:

```bash
sudo docker network create --driver=bridge --subnet=192.168.128.0/24 --gateway=192.168.128.1 br_dashboard
```

### Start the data layer

```bash
cd /home/winlab/Taipei-City-Dashboard/docker
sudo docker compose -f docker-compose-db.yaml up -d redis postgres-data postgres-manager
```

Verify all three containers have port bindings (`sudo docker ps`). If `redis` shows no ports:

```bash
sudo docker network connect br_dashboard redis
```

### Initialize / refresh the YouBike data layer (one command)

Real CSV snapshots live on `winlab@192.168.10.71:~/hackathon-pipeline/data/`. Pull them into `data/`, then run the bootstrap script:

```bash
rsync -ah winlab@192.168.10.71:hackathon-pipeline/data/youbike_Taipei    data/
rsync -ah winlab@192.168.10.71:hackathon-pipeline/data/youbike_NewTaipei data/
./scripts/load-ubike-data.sh
```

`scripts/load-ubike-data.sh` is idempotent and does the following:

1. Creates the `hackathon` database (if missing).
2. Seeds `dashboardmanager` with the timemap component and the "Youbike Analysis" dashboard.
3. Initializes the `youbike_snapshots` schema and indexes.
4. Loads every CSV under `data/youbike_{Taipei,NewTaipei}/`.
5. Fills missing 15-min slots so every slider tick has data.

CSV files are not committed. The script aborts with instructions if `data/` is empty — for a quick demo you can drop a handful of CSVs into the two subdirs and the gap-fill step will project them across all 96 quarter-hour slots.

Useful env overrides: `PG_CONTAINER`, `PG_USER`, `HACKATHON_DB`, `MANAGER_DB`, `DATA_DIR`, `DOCKER`.

### Start the backend

The backend requires several env vars. Run from `Taipei-City-Dashboard-BE/`:

```bash
REDIS_HOST=localhost \
DB_MANAGER_HOST=localhost DB_MANAGER_PORT=5432 \
DB_MANAGER_USER=postgres DB_MANAGER_PASSWORD=postgres DB_MANAGER_DBNAME=dashboardmanager \
DB_DASHBOARD_HOST=localhost DB_DASHBOARD_PORT=5433 \
DB_DASHBOARD_USER=postgres DB_DASHBOARD_PASSWORD=postgres DB_DASHBOARD_DBNAME=dashboard \
go run main.go
```

The hackathon DB shares the manager Postgres instance, so it reuses `DB_MANAGER_*` credentials (the `hackathon` DB name is the default). `postgres-data` is published on host port **5433** while `postgres-manager` is on **5432** (see `sudo docker ps`).

The ONNX model path (`LM_MODEL_PATH`) is optional — if the `.so` is missing, the backend starts without AI search (graceful fallback).

### Start the frontend

Use `LOCAL_BACKEND=true` to proxy to the local Go server on port 3000 (instead of production):

```bash
cd Taipei-City-Dashboard-FE
LOCAL_BACKEND=true npm run dev
```

Frontend is at `http://localhost:3000`. Login: `admin@example.com` / `Admin123!`

### tmux session layout (convenience)

```
window 0: backend (go run main.go + env vars)
window 1: frontend (LOCAL_BACKEND=true npm run dev)
window 2: shell
```

### Vite proxy behavior (important gotcha)

The Vite dev proxy in `LOCAL_BACKEND=true` mode is configured as:

```js
"/api": {
    target: "http://localhost:8080/api/v1",
    rewrite: (path) => path.replace(/^\/api/, "")
}
```

The proxy **prepends the target's path** to the rewritten path. So:
- Request: `GET /api/commute/youbike/map` → rewrite → `/commute/youbike/map`
- Final URL: `http://localhost:8080/api/v1/commute/youbike/map` ✓

This means `api_endpoint` values stored in `component_maps` must be `/commute/...` form (no `/v1` prefix), and must start with `/api` so the proxy intercepts them. **Do not store `/api/v1/...` in `api_endpoint`** — that produces a double `/v1`.

---

## Commands

### Frontend

```bash
cd Taipei-City-Dashboard-FE
LOCAL_BACKEND=true npm run dev   # Local dev (port 3000, proxies to localhost:8080)
npm run dev                      # Production proxy (port 80, proxies to citydashboard.taipei)
npm run build                    # ESLint fix + Vite production build
npm run lint                     # ESLint auto-fix only
```

No test framework is configured in the frontend.

### Backend

```bash
cd Taipei-City-Dashboard-BE
go run main.go                  # Start API server (port 8080)
go run main.go migrateDB        # Run manager DB migrations
go run main.go initDashboard    # Seed dashboard sample data
go build -v ./...               # Build check (used in CI)
```

No dedicated test suite; CI runs `go build`.

### Docker (full-stack alternative)

```bash
docker compose -f docker/docker-compose-init.yaml up   # Initialize DBs + npm install
docker compose -f docker/docker-compose-db.yaml up -d  # Data layer only
docker compose -f docker/docker-compose.yaml up -d     # Full stack (Nginx, FE, BE)
```

Copy `docker/.env.template` to `docker/.env` and fill in secrets before starting.

---

## Architecture

### Frontend–Backend Communication

The Vite dev proxy rewrites `/api/*` → `http://localhost:8080/api/v1/*` (local) or `https://citydashboard.taipei/api/v1/*` (production). In Docker Compose it targets `http://dashboard-be:8080`.

All HTTP calls go through the single Axios instance at `src/router/axios.js` (`http`), which:
- Has `baseURL: '/api'` (from `VITE_API_URL` env var)
- Attaches `Authorization: Bearer {token}` on every request
- Extracts a refreshed JWT from `response.data.token` and persists it to `localStorage`
- Maps status codes to store-level error flags (401 → logout, 429 → rate-limit notice)

**Use the `http` instance** (not raw `axios`) for API calls so the base URL and auth header are applied.

### State Management (Pinia stores)

| Store | Responsibility |
|---|---|
| `authStore` | JWT token, user object, mobile detection |
| `contentStore` | Dashboards, components, chart data, global `loading`/`error` flags |
| `mapStore` | Mapbox/deck.gl layer configs, GeoJSON sources |
| `adminStore` | Admin CRUD for dashboards and components |
| `dialogStore` | Modal/notification queue |
| `chatStore` | AI chat feature state |

### Backend Layers

```
controllers/   HTTP handlers (bind JSON, call models, return gin.H{})
models/        GORM queries against two DB connections: DBDashboard / DBManager
routes/        Gin route registration + middleware wiring
services/      AI/vector search business logic (Qdrant, ONNX, LangChain)
cache/         Redis read/write helpers
middleware/    JWT validation, rate limiting, CORS, IP sanitization
initial/       DB migrations, cron job setup, sample data seeding
```

Three separate PostgreSQL instances are used:
- `dashboard` DB — component chart data and history
- `manager` DB — users, dashboard configs, issues, contributors
- `hackathon` DB — hackathon/demo features (e.g. `youbike_snapshots`); non-panicking connect via `ConnectToHackathonDB()`

### AI/ML Pipeline in Backend

The Go binary optionally loads an ONNX e5 model for semantic embedding. `InitLmSession()` and `InitTokenizer()` return `nil` (with a log warning) if the shared library or model files are missing — the backend starts normally without AI search. `GenVector()` guards against nil session before running inference.

### Map Layer Source Types

`component_maps.source` controls how `mapStore.addToMapLayerList()` loads data:

| Source value | Behavior |
|---|---|
| `"geojson"` | Fetches `/mapData/{index}.geojson` from Vite static |
| `"raster"` | Adds a tile source |
| `"api"` | Calls `fetchApiGeoJson(map_config)` → hits `api_endpoint` for current-hour GeoJSON |

The `api_endpoint` column in `component_maps` was added via `ALTER TABLE component_maps ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR` (in `youbike-timemap-seed.sql`).

### Layer ID pattern

`layerId` is computed as `${index}-${type}-${city}` throughout mapStore and chart components. The `city` field comes from `component_maps` which has no city column, so it is always `undefined`, yielding e.g. `youbike_timemap-circle-undefined`. This is consistent and intentional.

### ETL (Airflow)

DAGs under `Taipei-City-Dashboard-DE/dags/` are auto-routed to Celery queues by schedule frequency:
- ≤10 min interval → `realtime` queue
- Daily → `default` or `heavy` (split 50/50 by DAG ID parity)
- Monthly+ → `heavy` queue

Shared operator patterns live in `dags/operators/`. City-specific pipelines are in `proj_city_dashboard/` (Taipei) and `proj_new_taipei_city_dashboard/` (New Taipei).

---

## Implemented Features

### YouBike 一日可用率動態地圖 (branch: `feat/ubike-time-series`)

A time-series map component showing YouBike station availability across 24 hours, with a drag slider and play/pause button.

**Files changed:**

| File | Change |
|------|--------|
| `Taipei-City-Dashboard-BE/app/controllers/commute.go` | New file — 3 handlers: `GetYouBikeMap`, `GetYouBikeShortage`, `GetYouBikeBlacklist` |
| `Taipei-City-Dashboard-BE/app/routes/router.go` | Added `configureCommuteRoutes()` — registers `/commute/youbike/{map,shortage,blacklist}` |
| `Taipei-City-Dashboard-BE/app/models/componentConfig.go` | Added `ApiEndpoint *string` to `ComponentMap` struct |
| `Taipei-City-Dashboard-BE/app/models/qdrant.go` | `InitLmSession` and `InitTokenizer` gracefully return `nil` instead of `log.Fatalf` when ONNX unavailable |
| `Taipei-City-Dashboard-FE/src/store/mapStore.js` | Added `source:"api"` branch in `addToMapLayerList`, `fetchApiGeoJson()`, and `updateTimeMapSource()` |
| `Taipei-City-Dashboard-FE/src/assets/configs/mapbox/mapConfig.js` | Added `circle-availability` paint entry |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/components/YouBikeTimeMap.vue` | New component — slider + play + legend |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/DashboardComponent.vue` | Registered `YouBikeTimeMap` chart type |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/utilities/chartTypes.ts` | Added `YouBikeTimeMap: "時間軸地圖"` |
| `Taipei-City-Dashboard-FE/vite.config.js` | Added `LOCAL_BACKEND=true` mode (port 3000, proxy to localhost:8080) |
| `scripts/load-ubike-data.sh` | One-shot bootstrap — creates DB, seeds dashboardmanager, loads CSVs from `data/`, gap-fills 15-min slots |
| `scripts/fill-missing-youbike-slots.sql` | Per (city × hour × quarter) gap-fill — copies a random same-city snapshot into each empty slot |
| `db-sample-data/youbike-timemap-seed.sql` | Idempotent seed for dashboardmanager: component, component_charts, component_maps (with api_endpoint), query_charts |
| `db-sample-data/youbike-analysis-dashboard.sql` | Idempotent seed: per-city "Youbike Analysis" dashboard tab |

**API endpoints:**

```
GET /api/v1/commute/youbike/map?city=all&hour=8
  → GeoJSON FeatureCollection with availability_pct, avg_available, total_docks per station

GET /api/v1/commute/youbike/shortage?city=all
  → { series: [{name, data:[{x:"0",y:pct},...]}], categories:["0"..."23"] }

GET /api/v1/commute/youbike/blacklist?city=all&limit=20
  → { data: [{x: station_name, y: empty_pct, city}] }
```

**Dashboard registration:**

Component `youbike_timemap` (ID=1) is in dashboards `map-layers-taipei` and `map-layers-metrotaipei`. Navigate to 台北市 → 圖資資訊 to see it.

**PostgreSQL gotcha:** `ROUND(double precision, integer)` doesn't exist — must cast first: `ROUND(value::numeric, 1)`.

---

## Key Conventions

### API response shape (backend)

```json
{ "data": {}, "token": "jwt_if_refreshed", "message": "status" }
```

Always return errors as `c.JSON(statusCode, gin.H{"message": "..."})`.

### Frontend component files

PascalCase `.vue` files with `<script setup>` (Composition API), scoped SCSS. Events use kebab-case (`@update-data`); props use camelCase.

### GORM models

Use `pq.Int64Array` for PostgreSQL `int[]` columns. Two global DB handles: `DBDashboard` and `DBManager` (initialized in `initial/`). A third optional handle `DBHackathon` is used for hackathon features.

### Authentication

- Email login: `POST /api/v1/auth/login` (HTTP Basic Auth header, method POST)
- Default admin: `admin@example.com` / `Admin123!` (set in `docker/.env`)
- OAuth (Taipei Pass / ISSO): callback exchanges code for JWT
- Admin routes are guarded by both JWT middleware and `IsSysAdm` middleware checking `is_admin` on the user record

### Adding a new chart type

1. Create `src/dashboardComponent/components/MyChart.vue` with props `["chart_config","activeChart","series","map_config","map_filter","map_filter_on"]`
2. Add `case "MyChart": return svg ? MapLegendSvg : MyChart;` in `DashboardComponent.vue`
3. Add `MyChart: "顯示名稱"` in `src/dashboardComponent/utilities/chartTypes.ts`
4. Add component row in `components` + `component_charts` + `query_charts` tables in dashboardmanager DB
5. Add component ID to a dashboard's `components` array

---

## Environment Variables

See `docker/.env.template` for the full list. Key groups:
- Frontend: `VITE_MAPBOXTOKEN`, `VITE_TAIPEIPASS_*`, `VITE_API_URL`
- Backend: `JWT_SECRET`, `IDNO_SALT`, Postgres credentials, Redis DSN, Qdrant host, TWCC API key
- Hackathon DB: shares the manager Postgres instance — reuses `DB_MANAGER_*`. Override the database name with `DB_HACKATHON_DBNAME` (defaults to `hackathon`).
