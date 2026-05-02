# YouBike Time-Series — Implementation Plan

Branch: `feat/ubike-time-series` (based on v3.1.9)

## Scope

Two modules from the 智慧通勤 theme:

| Module | Type | Risk | Status |
|--------|------|------|--------|
| **M2** YouBike 一日動態地圖 | Map (Mapbox circle layer + time slider) | Low — lat/lon already in DB | ✅ data ready |
| **M4** YouBike 缺車時段排名 | Chart (Heatmap + Bar) | Low — no geometry needed | ✅ data ready |

Data already collected: `youbike_snapshots` — 13,896 rows (Taipei, 1,737 站) + 10,668 rows (NewTaipei, 1,524 站), updated every 30 min.

---

## Phase 1 — Backend API (target: 3 hours)

### File: `Taipei-City-Dashboard-BE/app/controllers/commute.go` (new)

Three handlers:

#### 1. `GetYouBikeMap`
```
GET /api/v1/commute/youbike/map?city=all&hour=8
```
- `city` ∈ {`Taipei`, `NewTaipei`, `all`}, default `all`
- `hour` ∈ [0,23], default = current hour (UTC+8)
- Query: group `youbike_snapshots` by station for the given hour, compute `availability_pct = AVG(available_bikes/total_docks)*100`
- Response: GeoJSON FeatureCollection — each station is a `Point` Feature with properties `station_uid`, `station_name`, `city`, `availability_pct`, `avg_available`, `total_docks`
- Color field: `"#ef4444"` (<10%), `"#f97316"` (10-30%), `"#22c55e"` (≥30%)

```sql
SELECT station_uid, station_name, lat, lon, city,
  ROUND(AVG(available_bikes::float / NULLIF(total_docks,0)) * 100, 1) AS availability_pct,
  ROUND(AVG(available_bikes), 0)                                       AS avg_available,
  MAX(total_docks)                                                      AS total_docks
FROM youbike_snapshots
WHERE (city = $1 OR $1 = 'all')
  AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') = $2
GROUP BY station_uid, station_name, lat, lon, city
ORDER BY availability_pct ASC;
```

#### 2. `GetYouBikeShortage`
```
GET /api/v1/commute/youbike/shortage?city=all
```
- Returns 24×2 heatmap data (hour × city)
- Each cell: `shortage_pct = empty_stations / total_stations * 100`
- Response shape for HeatmapChart: `{ series: [{ name: "Taipei", data: [{x:"0",y:12.3}, ...] }, { name: "NewTaipei", data: [...] }] }`

```sql
SELECT EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int AS hour,
       city,
       COUNT(DISTINCT station_uid) FILTER (WHERE available_bikes = 0) AS empty_stations,
       COUNT(DISTINCT station_uid)                                      AS total_stations
FROM youbike_snapshots
WHERE (city = $1 OR $1 = 'all')
GROUP BY 1, 2
ORDER BY 1, 2;
```

#### 3. `GetYouBikeBlacklist`
```
GET /api/v1/commute/youbike/blacklist?city=all&limit=20
```
- TOP N stations by `empty_pct` (available_bikes = 0)
- Response: `{ data: [{ station_uid, station_name, city, lat, lon, empty_pct, empty_count, total_count }] }` — BarChart-compatible

```sql
SELECT station_uid, station_name, city, lat, lon,
  COUNT(*) FILTER (WHERE available_bikes = 0)                                     AS empty_count,
  COUNT(*)                                                                         AS total_count,
  ROUND(COUNT(*) FILTER (WHERE available_bikes=0)*100.0 / NULLIF(COUNT(*),0), 1) AS empty_pct
FROM youbike_snapshots
WHERE (city = $1 OR $1 = 'all')
GROUP BY station_uid, station_name, city, lat, lon
HAVING COUNT(*) > 2
ORDER BY empty_pct DESC
LIMIT $2;
```

### File: `Taipei-City-Dashboard-BE/app/routes/router.go` (edit)

Add `configureCommuteRoutes()` call inside `ConfigureRoutes()`, and add the new function:

```go
func configureCommuteRoutes() {
    commuteRoutes := RouterGroup.Group("/commute")
    commuteRoutes.Use(middleware.LimitAPIRequests(30, global.LimitRequestsDuration))
    commuteRoutes.Use(middleware.LimitTotalRequests(200, global.TokenExpirationDuration))
    {
        commuteRoutes.GET("/youbike/map",       controllers.GetYouBikeMap)
        commuteRoutes.GET("/youbike/shortage",  controllers.GetYouBikeShortage)
        commuteRoutes.GET("/youbike/blacklist", controllers.GetYouBikeBlacklist)
    }
}
```

### DB indexes (run once on hackathon DB)

```sql
CREATE INDEX IF NOT EXISTS idx_youbike_hour
  ON youbike_snapshots (city, (EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')));

CREATE INDEX IF NOT EXISTS idx_youbike_available
  ON youbike_snapshots (city, available_bikes, snapshot_at);
```

---

## Phase 2 — Frontend: M2 YouBike 一日動態地圖 (target: 5 hours)

### File: `Taipei-City-Dashboard-FE/src/dashboardComponent/components/YouBikeTimeMap.vue` (new)

Custom chart type that renders a Mapbox circle layer driven by a 24-hour time slider.

**Props** (same as all dashboard components):
```js
defineProps(["chart_config", "activeChart", "series", "map_config", "map_filter", "map_filter_on"])
```

**State:**
- `currentHour` — reactive, drives API fetch
- `allHoursData` — cache: `Map<hour, GeoJSON>` for play mode
- `playing` — bool, auto-advance timer

**Mapbox setup:**
- Source ID: `youbike-timemap`
- Layer: `circle` paint driven by `availability_pct`
  ```js
  "circle-color": ["step", ["get", "availability_pct"],
    "#ef4444", 10, "#f97316", 30, "#22c55e"]
  "circle-radius": ["interpolate", ["linear"], ["get", "total_docks"], 10, 4, 50, 9]
  ```

**Time slider UI:**
- `<input type="range" min="0" max="23" v-model="currentHour" />`
- Display: `00:00 — 23:00` labels
- Play button: `setInterval` every 800ms, increments hour mod 24
- On play start: prefetch all 24 hours and fill `allHoursData` cache

**API call:**
- On `currentHour` change (debounce 200ms): `GET /api/v1/commute/youbike/map?city=all&hour={h}`
- Use `allHoursData` cache if available (play mode)

**Popup on circle click:** station name, city, available / total, availability %

### Register new component type

File: `Taipei-City-Dashboard-FE/src/dashboardComponent/index.js` (or wherever chart types are registered)

Add `YouBikeTimeMap` to the component type map.

### Dashboard seed entry (add to DB via migration or admin UI)

```json
{
  "index": "youbike_timemap",
  "name": "YouBike 一日可用率動態地圖",
  "chart_config": {
    "types": ["YouBikeTimeMap"],
    "color": ["#22c55e", "#f97316", "#ef4444"]
  },
  "map_config": [{
    "type": "custom-timemap",
    "source": "api",
    "api_endpoint": "/api/v1/commute/youbike/map"
  }]
}
```

---

## Phase 3 — Frontend: M4 YouBike 缺車時段排名 (target: 2 hours)

Uses **existing** `HeatmapChart.vue` and `BarChart.vue` — no new component needed.

### Backend data shaping

`GetYouBikeShortage` formats response to match HeatmapChart's expected `series` format:
```json
{
  "series": [
    { "name": "Taipei",    "data": [{"x":"0","y":8.2}, {"x":"1","y":6.1}, ...] },
    { "name": "NewTaipei", "data": [{"x":"0","y":5.3}, ...] }
  ],
  "categories": ["0","1","2",...,"23"]
}
```

`GetYouBikeBlacklist` formats for BarChart:
```json
{
  "data": [
    { "x": "台北車站(博愛路)", "y": 87.5, "city": "Taipei" },
    ...
  ]
}
```

### Dashboard seed entries

```json
[
  {
    "index": "youbike_shortage_heatmap",
    "name": "YouBike 缺車時段熱力圖",
    "chart_config": {
      "types": ["HeatmapChart"],
      "color": ["#22c55e", "#f97316", "#ef4444"],
      "categories": ["0","1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23"],
      "unit": "%",
      "description": "各時段雙北 YouBike 缺車率（available_bikes=0 站數 / 總站數）"
    },
    "api_endpoint": "/api/v1/commute/youbike/shortage"
  },
  {
    "index": "youbike_blacklist",
    "name": "YouBike 缺車黑名單站 TOP 20",
    "chart_config": {
      "types": ["BarChart"],
      "color": ["#ef4444"],
      "unit": "%",
      "description": "歷史缺車率最高的 20 個站點"
    },
    "api_endpoint": "/api/v1/commute/youbike/blacklist?limit=20"
  }
]
```

---

## File Change Summary

| File | Action |
|------|--------|
| `Taipei-City-Dashboard-BE/app/controllers/commute.go` | Create — 3 handlers |
| `Taipei-City-Dashboard-BE/app/routes/router.go` | Edit — add `configureCommuteRoutes()` |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/components/YouBikeTimeMap.vue` | Create — custom map+slider component |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/index.js` | Edit — register `YouBikeTimeMap` type |
| DB (hackathon-pipeline) | Add 2 indexes + seed 3 component rows |

---

## Implementation Order

1. `commute.go` — write and `go build` to verify (no frontend needed)
2. `router.go` — wire routes, smoke-test with `curl`
3. `YouBikeTimeMap.vue` — implement map + slider, connect to real API
4. Register type, add dashboard seed data, verify in UI
5. Shape shortage/blacklist responses → verify HeatmapChart + BarChart render
6. Add Mapbox popup + legend labels
7. Manual test: play mode caches all 24h, slider debounce, city toggle

## Known Risks

- `YouBikeTimeMap` requires Mapbox map instance access from inside a dashboard component — check how existing map-aware components (`DistrictChart`, `MapLegend`) get the map ref, replicate the pattern.
- The existing component data pipeline (`/api/v1/components/:id/chart`) uses a generic SQL query stored in DB. The new `/commute/youbike/*` endpoints bypass this and return custom shapes. Confirm the FE component can be configured to call a direct API endpoint rather than going through the generic chart pipeline.
