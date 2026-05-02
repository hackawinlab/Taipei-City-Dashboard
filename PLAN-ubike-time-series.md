# YouBike Time-Series — Implementation Plan

Branch: `feat/ubike-time-series` (based on v3.1.9)

## Reference UI

Checked `https://citydashboard.taipei/mapview?index=youbike&city=taipei`:
- Left panel (`.map-charts`, 360px wide in `MapView.vue`) lists `DashboardComponent` cards
- When a card is toggled ON, it expands and renders the chart component inside the card
- The YouBike card shows a donut chart → **we replace this with a time slider for our new component**
- Map shows color-coded circle markers (green/yellow/red)

## Scope

Two modules from the 智慧通勤 theme:

| Module | Type | Risk | Status |
|--------|------|------|--------|
| **M2** YouBike 一日動態地圖 | Left panel slider → Mapbox circle layer | Low — lat/lon in DB | ✅ data ready |
| **M4** YouBike 缺車時段排名 | Heatmap + Bar chart (reuse existing types) | Low | ✅ data ready |

Data: `youbike_snapshots` — 13,896 rows (Taipei, 1,737 站) + 10,668 (NewTaipei, 1,524 站), every 30 min.

---

## Architecture Overview

```
MapView.vue (.map-charts panel, 360px)
  └─ DashboardComponent (card, toggled ON)
       └─ YouBikeTimeMap.vue  ← renders slider UI in the card
            │  drag slider → fetch /api/v1/commute/youbike/map?hour=X
            └─ mapStore.updateTimeMapSource(layerId, geojson)
                 └─ map.getSource(`${layerId}-source`).setData(geojson)
                      └─ Mapbox re-renders circles with new availability colors
```

Toggle ON → `mapStore.addToMapLayerList(map_config)` → new `source: "api"` branch → initial fetch + circle layer added to map.

---

## Phase 1 — Backend API (target: 3 hours)

### File: `Taipei-City-Dashboard-BE/app/controllers/commute.go` (new)

Three handlers:

#### `GetYouBikeMap`
```
GET /api/v1/commute/youbike/map?city=all&hour=8
```
- `city` ∈ {`Taipei`, `NewTaipei`, `all`}, default `all`
- `hour` ∈ [0,23], default = current hour (UTC+8)
- Response: GeoJSON FeatureCollection — each station is a `Point` Feature

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

Response shape (GeoJSON FeatureCollection):
```json
{
  "type": "FeatureCollection",
  "features": [{
    "type": "Feature",
    "geometry": { "type": "Point", "coordinates": [121.517, 25.048] },
    "properties": {
      "station_uid": "500101001",
      "station_name": "捷運市政府站(2號出口)",
      "city": "Taipei",
      "availability_pct": 72.4,
      "avg_available": 8,
      "total_docks": 14
    }
  }]
}
```

#### `GetYouBikeShortage`
```
GET /api/v1/commute/youbike/shortage?city=all
```
Returns 24×2 heatmap data shaped for `HeatmapChart.vue`:
```json
{
  "series": [
    { "name": "Taipei",    "data": [{"x":"0","y":8.2}, {"x":"1","y":6.1}, ...] },
    { "name": "NewTaipei", "data": [{"x":"0","y":5.3}, ...] }
  ],
  "categories": ["0","1",...,"23"]
}
```

#### `GetYouBikeBlacklist`
```
GET /api/v1/commute/youbike/blacklist?city=all&limit=20
```
Returns top-N stations by empty rate, shaped for `BarChart.vue`:
```json
{
  "data": [{ "x": "台北車站(博愛路)", "y": 87.5, "city": "Taipei" }]
}
```

### File: `Taipei-City-Dashboard-BE/app/routes/router.go` (edit)

Add inside `ConfigureRoutes()`:
```go
configureCommuteRoutes()
```

Add new function:
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

### 2-A. `mapStore.js` — add `source: "api"` support

In `addToMapLayerList()`, after the existing `else if (element.source === "raster")` branch, add:

```js
} else if (element.source === "api") {
    this.fetchApiGeoJson(appendLayer);
}
```

Add two new store actions:

```js
// Initial fetch for an API-sourced layer (called on toggle ON)
async fetchApiGeoJson(map_config) {
    try {
        const hour = new Date().toLocaleString("en-US", {
            timeZone: "Asia/Taipei", hour: "numeric", hour12: false
        });
        const res = await axios.get(
            `${map_config.api_endpoint}?city=all&hour=${hour}`
        );
        this.map.addSource(`${map_config.layerId}-source`, {
            type: "geojson",
            data: res.data,
        });
        this.addMapLayer(map_config);
    } catch (e) {
        console.error("fetchApiGeoJson failed", e);
    } finally {
        this.loadingLayers = this.loadingLayers.filter(
            (el) => el !== map_config.layerId
        );
    }
},

// Called by YouBikeTimeMap when slider changes
updateTimeMapSource(layerId, geojsonData) {
    const source = this.map.getSource(`${layerId}-source`);
    if (source) source.setData(geojsonData);
},
```

### 2-B. `mapConfig.js` — add circle paint for availability

In `/src/assets/configs/mapbox/mapConfig.js`, add a new paint entry:

```js
"circle-availability": {
    "circle-color": [
        "step", ["get", "availability_pct"],
        "#ef4444",   // 0–9%: red
        10, "#f97316", // 10–29%: orange
        30, "#22c55e"  // ≥30%: green
    ],
    "circle-radius": [
        "interpolate", ["linear"], ["get", "total_docks"],
        10, 4,
        50, 9
    ],
    "circle-opacity": 0.85,
    "circle-stroke-width": 1,
    "circle-stroke-color": "#1a1a1a",
},
```

### 2-C. `YouBikeTimeMap.vue` — the chart component

**File:** `src/dashboardComponent/components/YouBikeTimeMap.vue`

This is the chart component rendered inside the DashboardComponent card when the YouBike time map layer is toggled on. It shows:
- A time slider (0–23h) with the current hour label
- Play/pause button
- A color legend (red/orange/green = availability)

```vue
<script setup>
import { ref, watch, onUnmounted } from "vue";
import { useMapStore } from "../../store/mapStore";
import http from "../../router/axios";

const props = defineProps(["chart_config", "activeChart", "series",
                           "map_config", "map_filter", "map_filter_on"]);

const mapStore = useMapStore();
const currentHour = ref(new Date().getHours());  // init to current local hour
const playing = ref(false);
const cache = ref({});   // Map<hour, GeoJSON>
let playTimer = null;

const layerId = computed(() =>
    props.map_config?.[0]
        ? `${props.map_config[0].index}-${props.map_config[0].type}-${props.map_config[0].city}`
        : null
);

// Fetch one hour's data; use cache if available
async function fetchHour(hour) {
    if (cache.value[hour]) {
        mapStore.updateTimeMapSource(layerId.value, cache.value[hour]);
        return;
    }
    const res = await http.get(
        `/commute/youbike/map?city=all&hour=${hour}`
    );
    cache.value[hour] = res.data;
    mapStore.updateTimeMapSource(layerId.value, res.data);
}

// Prefetch all 24h for play mode
async function prefetchAll() {
    for (let h = 0; h < 24; h++) {
        if (!cache.value[h]) {
            const res = await http.get(`/commute/youbike/map?city=all&hour=${h}`);
            cache.value[h] = res.data;
        }
    }
}

watch(currentHour, (h) => fetchHour(h));

function togglePlay() {
    if (playing.value) {
        clearInterval(playTimer);
        playing.value = false;
    } else {
        playing.value = true;
        prefetchAll();
        playTimer = setInterval(() => {
            currentHour.value = (currentHour.value + 1) % 24;
        }, 800);
    }
}

onUnmounted(() => clearInterval(playTimer));
</script>

<template>
  <div class="youbike-timemap">
    <div class="youbike-timemap-header">
      <span class="hour-label">{{ String(currentHour).padStart(2,"0") }}:00</span>
      <button class="play-btn" @click="togglePlay">
        <span>{{ playing ? "pause" : "play_arrow" }}</span>
      </button>
    </div>
    <div class="youbike-timemap-slider">
      <span>00</span>
      <input
        type="range"
        min="0"
        max="23"
        step="1"
        v-model.number="currentHour"
        @mousedown="playing && togglePlay()"
      />
      <span>23</span>
    </div>
    <div class="youbike-timemap-legend">
      <span class="dot red" />  缺車 (&lt;10%)
      <span class="dot orange" /> 普通 (10–30%)
      <span class="dot green" />  充足 (≥30%)
    </div>
  </div>
</template>

<style scoped lang="scss">
.youbike-timemap {
    padding: var(--font-s);
    display: flex;
    flex-direction: column;
    row-gap: var(--font-s);

    &-header {
        display: flex;
        align-items: center;
        justify-content: space-between;

        .hour-label {
            font-size: var(--font-xl);
            font-weight: 700;
            color: var(--color-highlight);
        }
        .play-btn span {
            font-family: var(--font-icon);
            font-size: 1.5rem;
            cursor: pointer;
            color: var(--color-highlight);
        }
    }

    &-slider {
        display: flex;
        align-items: center;
        column-gap: var(--font-s);

        input[type="range"] {
            flex: 1;
            accent-color: var(--color-highlight);
            height: 4px;
            cursor: pointer;
        }
        span { font-size: var(--font-s); color: var(--color-complement-text); }
    }

    &-legend {
        display: flex;
        align-items: center;
        column-gap: var(--font-ms);
        font-size: var(--font-s);
        color: var(--color-complement-text);

        .dot {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            &.red    { background: #ef4444; }
            &.orange { background: #f97316; }
            &.green  { background: #22c55e; }
        }
    }
}
</style>
```

### 2-D. Register in `DashboardComponent.vue`

Find where `chart_config.types[0]` is mapped to a component — add `YouBikeTimeMap` to the import and the component map. The exact registration file may be `src/dashboardComponent/DashboardComponent.vue` or the chart-type switch inside it.

### 2-E. Dashboard seed data

Component DB entry (insert via admin or migration):
```json
{
  "index": "youbike_timemap",
  "name": "YouBike 一日可用率動態地圖",
  "chart_config": {
    "types": ["YouBikeTimeMap"],
    "color": ["#22c55e", "#f97316", "#ef4444"]
  },
  "map_config": [{
    "index":        "youbike_timemap",
    "type":         "circle",
    "source":       "api",
    "api_endpoint": "/api/v1/commute/youbike/map",
    "city":         "taipei",
    "icon":         "availability",
    "size":         "availability",
    "paint": {
      "circle-color": [
        "step", ["get", "availability_pct"],
        "#ef4444", 10, "#f97316", 30, "#22c55e"
      ],
      "circle-radius": [
        "interpolate", ["linear"], ["get", "total_docks"], 10, 4, 50, 9
      ],
      "circle-opacity": 0.85,
      "circle-stroke-width": 1,
      "circle-stroke-color": "#1a1a1a"
    }
  }]
}
```

The `paint` field is already merged into the layer config in the existing `addMapLayer()` via `...map_config.paint`.

---

## Phase 3 — Frontend: M4 YouBike 缺車時段排名 (target: 2 hours)

Uses **existing** `HeatmapChart.vue` and `BarChart.vue` — no new component needed.

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
      "unit": "%"
    },
    "map_config": []
  },
  {
    "index": "youbike_blacklist",
    "name": "YouBike 缺車黑名單站 TOP 20",
    "chart_config": {
      "types": ["BarChart"],
      "color": ["#ef4444"],
      "unit": "%"
    },
    "map_config": []
  }
]
```

Both components use the generic chart pipeline (`/api/v1/components/:id/chart`) — the backend query stored in the component's DB record points to a custom SQL that calls `GetYouBikeShortage` / `GetYouBikeBlacklist` logic. Alternatively, add a `source: "custom-api"` type to the FE chart data fetching, following the same pattern as the map layer `source: "api"`.

---

## File Change Summary

| File | Action |
|------|--------|
| `Taipei-City-Dashboard-BE/app/controllers/commute.go` | **Create** — 3 handlers |
| `Taipei-City-Dashboard-BE/app/routes/router.go` | **Edit** — add `configureCommuteRoutes()` |
| `Taipei-City-Dashboard-FE/src/store/mapStore.js` | **Edit** — add `source:"api"` branch, `fetchApiGeoJson`, `updateTimeMapSource` |
| `Taipei-City-Dashboard-FE/src/assets/configs/mapbox/mapConfig.js` | **Edit** — add `circle-availability` paint config |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/components/YouBikeTimeMap.vue` | **Create** — slider UI + map update |
| `Taipei-City-Dashboard-FE/src/dashboardComponent/DashboardComponent.vue` | **Edit** — register `YouBikeTimeMap` type |
| DB (hackathon-pipeline) | Add 2 indexes + seed 3 component rows |

---

## Implementation Order

1. `commute.go` + `router.go` → `go build` to verify, smoke-test with `curl`
2. `mapStore.js` — add `source:"api"`, `fetchApiGeoJson`, `updateTimeMapSource`
3. `mapConfig.js` — add circle-availability paint
4. `YouBikeTimeMap.vue` — slider UI, connects to `mapStore.updateTimeMapSource`
5. `DashboardComponent.vue` — register the new type
6. Insert component seed data → verify toggle-on shows map + slider
7. Verify: drag slider → map colors update; play mode cycles 24h
8. M4: shape shortage/blacklist API responses, verify HeatmapChart + BarChart render

## Known Risks

| Risk | Mitigation |
|------|-----------|
| `mapStore.updateTimeMapSource` called before the source is added (layer not yet loaded) | Guard with `if (source)` check; retry after 200ms if null |
| Rapid slider drag fires many concurrent fetches | `debounce(fetchHour, 200)` on `watch(currentHour)` |
| Play mode prefetch rate-limit (30 RPM limit on backend) | Prefetch sequentially with 100ms delay between requests; 24 requests = well under limit |
| `DashboardComponent` chart type switch location | Read `DashboardComponent.vue` to confirm import pattern before Phase 2-D |
