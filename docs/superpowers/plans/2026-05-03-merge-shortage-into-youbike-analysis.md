# 將「YouBike 缺車成因分析」整合進「Youbike Analysis」— 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `youbike_persistence`（長時段缺車站排行）與 `youbike_imbalance`（站點淨流出量排行）兩個 block 變成 BE 真實 component，併入 `youbike-analysis-{taipei,metrotaipei}` dashboard，並移除原本純前端的 `youbike-shortage-analysis-*` shim。

**Architecture:** 新增 `component_charts.api_endpoint` 欄位（鏡像 `component_maps.api_endpoint`）。FE chart-data fetch 看到此欄位有值就改打該 URL 而非 `/component/{id}/chart`。BE 新增兩條 thin endpoint（`/commute/youbike/persistence`、`/commute/youbike/imbalance`），內部抽出共用的 aggregate-with-cache helper，回傳標準 chart-data 形狀。dashboardmanager DB 用 idempotent seed 加 2 個 component + 2 個 component_charts + 4 個 query_charts 並把兩 dashboard 的 components 陣列改成 6 個 id。

**Tech Stack:** Go 1.x (Gin / GORM)、PostgreSQL、Vue 3 / Pinia / Axios、bash seed scripts。

**Spec reference:** `docs/superpowers/specs/2026-05-03-merge-shortage-into-youbike-analysis-design.md`

**Codebase notes:**
- 沒有 unit test framework；CI 跑 `go build -v ./...` 與 `npm run build` 兩個編譯檢查。本計畫的「驗證」用 `go build` + `curl` + 瀏覽器手測。
- 按 user feedback memory：commit 用 `git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit ...` inline 設身分。
- 部署模式：BE/FE 都在 docker container 跑 dev；BE 改 Go code 後要 `sudo docker restart dashboard-be`；FE Vite hot-reload 不需重啟。

---

## File Structure

**新建：**
- `db-sample-data/youbike-shortage-blocks-seed.sql` — DB seed（schema + components + dashboard 陣列調整）

**修改（BE）：**
- `Taipei-City-Dashboard-BE/app/models/componentConfig.go` — `ComponentChart` struct 加 `ApiEndpoint *string` 欄位
- `Taipei-City-Dashboard-BE/app/controllers/commute.go` — 抽 `getYouBikeAggregatePayload` helper、新增 `GetYouBikePersistenceChart` / `GetYouBikeImbalanceChart` 兩個 controller
- `Taipei-City-Dashboard-BE/app/routes/router.go` — 在 `configureCommuteRoutes` 註冊兩條新路由

**修改（FE）：**
- `Taipei-City-Dashboard-FE/src/store/contentStore.js` — 在 `setCurrentDashboardAllChartData` 加 `api_endpoint` 分支（先附加，再清掉 shim）
- `Taipei-City-Dashboard-FE/src/views/DashboardView.vue` — 拿掉 `isYoubikeShortageIndex` 兩處 favorite-btn 條件與 import

**修改（infra/docs）：**
- `scripts/load-ubike-data.sh` — 在 step 2 多跑一條 seed 檔
- `STORY-youbike-shortage-dashboard.md` — 標題保留，內容指向更新
- `CLAUDE.md` — 加上 `component_charts.api_endpoint` 規約一段

**刪除：**
- `Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js`

---

## Task 1: BE — `ComponentChart` 加 `ApiEndpoint` 欄位

**Files:**
- Modify: `Taipei-City-Dashboard-BE/app/models/componentConfig.go:99-104`

- [ ] **Step 1: 改 struct**

把這段（第 99-104 行）：

```go
// ComponentChart is the model for the component_charts table.
type ComponentChart struct {
	Index string         `json:"index"      gorm:"column:index;type:varchar;primaryKey"     `
	Color pq.StringArray `json:"color" gorm:"column:color;type:varchar[]"`
	Types pq.StringArray `json:"types" gorm:"column:types;type:varchar[]"`
	Unit  string         `json:"unit" gorm:"column:unit;type:varchar"`
}
```

改成：

```go
// ComponentChart is the model for the component_charts table.
type ComponentChart struct {
	Index       string         `json:"index"      gorm:"column:index;type:varchar;primaryKey"     `
	Color       pq.StringArray `json:"color" gorm:"column:color;type:varchar[]"`
	Types       pq.StringArray `json:"types" gorm:"column:types;type:varchar[]"`
	Unit        string         `json:"unit" gorm:"column:unit;type:varchar"`
	ApiEndpoint *string        `json:"api_endpoint" gorm:"column:api_endpoint;type:varchar"`
}
```

註：`ApiEndpoint` 用 `*string` 是為了讓既有 row（沒有 api_endpoint）能 marshal 成 `null` 而非空字串，跟 `ComponentMap.ApiEndpoint` 同模式。

- [ ] **Step 2: `go build` 驗證**

```bash
cd Taipei-City-Dashboard-BE && go build -v ./...
```

Expected: 編譯成功，無錯。

- [ ] **Step 3: 不 commit，併入 Task 3 一起 commit**

---

## Task 2: BE — 抽 aggregate cache helper

**Files:**
- Modify: `Taipei-City-Dashboard-BE/app/controllers/commute.go:460-517`

抽出 `GetYouBikeShortageAnalysis` 內部「load + cache + aggregate」流程成共用 helper，讓 Task 3 的兩條新 controller 能 reuse 同一份 cache，避免每次切 dashboard 都重算。

- [ ] **Step 1: 在 commute.go 第 462 行（`shortageCacheTTL` 常數宣告）之後、`GetYouBikeShortageAnalysis` 之前，插入 helper**

```go
// getYouBikeAggregatePayload returns the cached aggregate payload, computing
// it on first call (or cache expiry). Shared by GetYouBikeShortageAnalysis,
// GetYouBikePersistenceChart, and GetYouBikeImbalanceChart so the three
// endpoints don't each maintain their own cache.
//
// Returns:
//   - payload: the aggregate result (zero-value on error)
//   - status:  HTTP status code to return on error (0 means OK)
//   - errMsg:  user-facing error message (empty when status==0)
func getYouBikeAggregatePayload(ctx context.Context) (youbike_aggregate.Payload, int, string) {
	if models.DBHackathon == nil {
		return youbike_aggregate.Payload{}, http.StatusServiceUnavailable, "hackathon database not available"
	}

	shortageCacheMu.Lock()
	if !shortageCachedAt.IsZero() && time.Since(shortageCachedAt) < shortageCacheTTL {
		cached := shortageCachedResult
		shortageCacheMu.Unlock()
		return cached, 0, ""
	}
	shortageCacheMu.Unlock()

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		return youbike_aggregate.Payload{}, http.StatusInternalServerError, fmt.Sprintf("db error: %v", err)
	}

	loadCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	snapshots, err := youbike_aggregate.LoadFromDB(loadCtx, sqlDB)
	if err != nil {
		return youbike_aggregate.Payload{}, http.StatusInternalServerError, fmt.Sprintf("load error: %v", err)
	}
	if len(snapshots) == 0 {
		return youbike_aggregate.Payload{}, http.StatusServiceUnavailable, "youbike_snapshots is empty — run scripts/load-ubike-data.sh first"
	}

	payload := youbike_aggregate.BuildPayload(snapshots)

	shortageCacheMu.Lock()
	shortageCachedAt = time.Now()
	shortageCachedResult = payload
	shortageCacheMu.Unlock()

	return payload, 0, ""
}
```

- [ ] **Step 2: 改 `GetYouBikeShortageAnalysis` 改用 helper**

把這段（從 `func GetYouBikeShortageAnalysis(c *gin.Context) {` 整個 function body）：

```go
func GetYouBikeShortageAnalysis(c *gin.Context) {
	if models.DBHackathon == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "hackathon database not available"})
		return
	}

	shortageCacheMu.Lock()
	if !shortageCachedAt.IsZero() && time.Since(shortageCachedAt) < shortageCacheTTL {
		cached := shortageCachedResult
		shortageCacheMu.Unlock()
		c.JSON(http.StatusOK, cached)
		return
	}
	shortageCacheMu.Unlock()

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("db error: %v", err)})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()
	snapshots, err := youbike_aggregate.LoadFromDB(ctx, sqlDB)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("load error: %v", err)})
		return
	}
	if len(snapshots) == 0 {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "youbike_snapshots is empty — run scripts/load-ubike-data.sh first"})
		return
	}

	payload := youbike_aggregate.BuildPayload(snapshots)

	shortageCacheMu.Lock()
	shortageCachedAt = time.Now()
	shortageCachedResult = payload
	shortageCacheMu.Unlock()

	c.JSON(http.StatusOK, payload)
}
```

改成：

```go
func GetYouBikeShortageAnalysis(c *gin.Context) {
	payload, status, errMsg := getYouBikeAggregatePayload(c.Request.Context())
	if status != 0 {
		c.JSON(status, gin.H{"message": errMsg})
		return
	}
	c.JSON(http.StatusOK, payload)
}
```

- [ ] **Step 3: `go build` 驗證**

```bash
cd Taipei-City-Dashboard-BE && go build -v ./...
```

Expected: 編譯成功。注意 `database/sql` 與 `context` import 仍被 helper 用到，不要動。

- [ ] **Step 4: 確認 import 沒有失去依賴**

```bash
grep -n '^import\|"context"\|"database/sql"\|"sync"' Taipei-City-Dashboard-BE/app/controllers/commute.go | head -10
```

Expected: `context`、`sync`、`fmt`、`time`、`net/http` 仍在 import block。`database/sql` 如果其他 controller 不用就可以移除——但 `GetYouBikeMap` 等 controller 也用到，應仍保留。如果 `go build` 過了就 OK。

- [ ] **Step 5: 不 commit，併入 Task 3 一起 commit**

---

## Task 3: BE — 兩條新 chart endpoint + route

**Files:**
- Modify: `Taipei-City-Dashboard-BE/app/controllers/commute.go`（檔尾追加）
- Modify: `Taipei-City-Dashboard-BE/app/routes/router.go:212-223`

- [ ] **Step 1: 在 `commute.go` 檔尾追加 chart-data response shape 與 city dataset key 的 helper**

```go
// chartTwoDimSeries / chartTwoDimResponse mirror the standard /component/:id/chart
// response shape (componentData.go's TwoDimensionalDataOutput) so frontend
// chart-data plumbing can consume api_endpoint replies without branching.
type chartTwoDimSeries struct {
	Name string                     `json:"name"`
	Data []chartTwoDimPoint         `json:"data"`
}

type chartTwoDimPoint struct {
	X string  `json:"x"`
	Y float64 `json:"y"`
}

type chartTwoDimResponse struct {
	Status     string              `json:"status"`
	Data       []chartTwoDimSeries `json:"data"`
	Categories []string            `json:"categories"`
}

// resolveYouBikeAggregateCity maps the dashboard's "?city=" query param onto
// the dataset key used inside aggregate.Payload (Taipei | NewTaipei | All).
//   - "taipei"        → "Taipei"
//   - "metrotaipei"   → "All" (the dual-city slice)
//   - empty / other   → "Taipei"
func resolveYouBikeAggregateCity(c *gin.Context) string {
	switch c.DefaultQuery("city", "taipei") {
	case "metrotaipei":
		return "All"
	default:
		return "Taipei"
	}
}
```

- [ ] **Step 2: 在 helper 之後追加 `GetYouBikePersistenceChart`**

```go
// GetYouBikePersistenceChart handles GET /api/v1/commute/youbike/persistence.
//
// Returns the chronic-shortage station ranking for the requested city slice
// in the standard chart-data response shape, so it can be consumed by frontend
// components whose component_charts.api_endpoint points here.
//
// Top 20 stations sorted by empty-hour ratio (desc), as built by
// aggregate.buildBarPersistence; y is the integer "empty hours" count.
func GetYouBikePersistenceChart(c *gin.Context) {
	payload, status, errMsg := getYouBikeAggregatePayload(c.Request.Context())
	if status != 0 {
		c.JSON(status, gin.H{"message": errMsg})
		return
	}

	cityKey := resolveYouBikeAggregateCity(c)
	rows := payload.BarPersistence[cityKey]
	const persistenceTopN = 20
	if len(rows) > persistenceTopN {
		rows = rows[:persistenceTopN]
	}

	points := make([]chartTwoDimPoint, 0, len(rows))
	categories := make([]string, 0, len(rows))
	for _, r := range rows {
		points = append(points, chartTwoDimPoint{X: r.StationName, Y: float64(r.EmptyHours)})
		categories = append(categories, r.StationName)
	}

	c.JSON(http.StatusOK, chartTwoDimResponse{
		Status:     "success",
		Data:       []chartTwoDimSeries{{Name: "缺車時數（小時）", Data: points}},
		Categories: categories,
	})
}
```

- [ ] **Step 3: 在 `GetYouBikePersistenceChart` 之後追加 `GetYouBikeImbalanceChart`**

```go
// GetYouBikeImbalanceChart handles GET /api/v1/commute/youbike/imbalance.
//
// Returns the borrow/return-imbalance ranking (top 15 stations by absolute
// imbalance) for the requested city slice in the standard chart-data response
// shape. y is the *negated* imbalance — preserving the frontend convention
// where "outflow" reads as a positive bar going right.
func GetYouBikeImbalanceChart(c *gin.Context) {
	payload, status, errMsg := getYouBikeAggregatePayload(c.Request.Context())
	if status != 0 {
		c.JSON(status, gin.H{"message": errMsg})
		return
	}

	cityKey := resolveYouBikeAggregateCity(c)
	cityBlock := payload.Imbalance[cityKey]
	rows := cityBlock["absolute"]
	const imbalanceTopN = 15
	if len(rows) > imbalanceTopN {
		rows = rows[:imbalanceTopN]
	}

	points := make([]chartTwoDimPoint, 0, len(rows))
	categories := make([]string, 0, len(rows))
	for _, r := range rows {
		points = append(points, chartTwoDimPoint{X: r.StationName, Y: float64(-r.Imbalance)})
		categories = append(categories, r.StationName)
	}

	c.JSON(http.StatusOK, chartTwoDimResponse{
		Status:     "success",
		Data:       []chartTwoDimSeries{{Name: "估計淨流出量", Data: points}},
		Categories: categories,
	})
}
```

- [ ] **Step 4: 在 `router.go:217-222` 註冊新路由**

把這段：

```go
		commuteRoutes.GET("/youbike/map", controllers.GetYouBikeMap)
		commuteRoutes.GET("/youbike/shortage", controllers.GetYouBikeShortage)
		commuteRoutes.GET("/youbike/blacklist", controllers.GetYouBikeBlacklist)
		commuteRoutes.GET("/youbike/station/:uid/hourly", controllers.GetYouBikeStationHourly)
		commuteRoutes.GET("/youbike/shortage-analysis", controllers.GetYouBikeShortageAnalysis)
```

改成：

```go
		commuteRoutes.GET("/youbike/map", controllers.GetYouBikeMap)
		commuteRoutes.GET("/youbike/shortage", controllers.GetYouBikeShortage)
		commuteRoutes.GET("/youbike/blacklist", controllers.GetYouBikeBlacklist)
		commuteRoutes.GET("/youbike/station/:uid/hourly", controllers.GetYouBikeStationHourly)
		commuteRoutes.GET("/youbike/shortage-analysis", controllers.GetYouBikeShortageAnalysis)
		commuteRoutes.GET("/youbike/persistence", controllers.GetYouBikePersistenceChart)
		commuteRoutes.GET("/youbike/imbalance", controllers.GetYouBikeImbalanceChart)
```

- [ ] **Step 5: `go build` 驗證**

```bash
cd Taipei-City-Dashboard-BE && go build -v ./...
```

Expected: 編譯成功，無錯。

- [ ] **Step 6: 重啟 dashboard-be 並用 curl 驗證 endpoint**

```bash
sudo docker restart dashboard-be
sleep 3  # wait for boot
curl -s 'http://localhost:8080/api/v1/commute/youbike/persistence?city=taipei' | jq '.status, .data[0].name, (.data[0].data | length), (.categories | length)'
```

Expected:
```
"success"
"缺車時數（小時）"
20
20
```

```bash
curl -s 'http://localhost:8080/api/v1/commute/youbike/imbalance?city=metrotaipei' | jq '.status, .data[0].name, (.data[0].data | length), (.data[0].data[0].y)'
```

Expected:
```
"success"
"估計淨流出量"
15
<some positive number, since y = -imbalance and absolute view sorts by most-negative imbalance first (largest outflow)>
```

如果 endpoint 回 `502 / 503 / 500`：先看 `sudo docker logs dashboard-be --tail 50`，常見原因是 `youbike_snapshots` 還沒 load（會回 503 with msg "youbike_snapshots is empty"），這時要先跑 `./scripts/load-ubike-data.sh`。

- [ ] **Step 7: Commit BE 三項一起**

```bash
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' add \
  Taipei-City-Dashboard-BE/app/models/componentConfig.go \
  Taipei-City-Dashboard-BE/app/controllers/commute.go \
  Taipei-City-Dashboard-BE/app/routes/router.go

git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit -m "$(cat <<'EOF'
feat(youbike-analysis): BE 加 component_charts.api_endpoint 與兩條 chart endpoint

- ComponentChart struct 新增 ApiEndpoint 欄位（鏡像 ComponentMap）
- 抽 getYouBikeAggregatePayload helper，三個 youbike aggregate-based endpoint 共用 cache
- 新增 /commute/youbike/persistence 與 /commute/youbike/imbalance，回傳標準 chart-data 形狀

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: DB — `youbike-shortage-blocks-seed.sql` 新增

**Files:**
- Create: `db-sample-data/youbike-shortage-blocks-seed.sql`
- Modify: `scripts/load-ubike-data.sh`（在 step 2 末尾多跑這支 seed）

- [ ] **Step 1: 建立 seed 檔**

寫到 `db-sample-data/youbike-shortage-blocks-seed.sql`：

```sql
-- YouBike 缺車成因分析 — 兩個 block（persistence、imbalance）作為真實 BE component
-- 併入 youbike-analysis-{taipei,metrotaipei} dashboard。
-- Run against dashboardmanager DB after dashboardmanager-demo.sql 與
-- youbike-analysis-dashboard.sql。
-- Idempotent：可重複執行。

-- 1. Schema migration（鏡像 component_maps.api_endpoint）
ALTER TABLE component_charts ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR;

-- 2. Component charts（types/color/unit + api_endpoint）
INSERT INTO component_charts (index, color, types, unit, api_endpoint)
VALUES
  ('youbike_persistence', '{"#ff6b6b"}', '{BarChart}', '小時', '/commute/youbike/persistence'),
  ('youbike_imbalance',   '{"#fb7185"}', '{BarChart}', '輛',   '/commute/youbike/imbalance')
ON CONFLICT (index) DO UPDATE
  SET color        = EXCLUDED.color,
      types        = EXCLUDED.types,
      unit         = EXCLUDED.unit,
      api_endpoint = EXCLUDED.api_endpoint;

-- 3. Components（id 由 sequence 分配；用 index 唯一鍵 idempotent upsert）
INSERT INTO components (index, name)
VALUES
  ('youbike_persistence', 'YouBike 長時段缺車站排行'),
  ('youbike_imbalance',   'YouBike 站點淨流出量排行')
ON CONFLICT (index) DO UPDATE
  SET name = EXCLUDED.name;

-- 4. Query charts（每 component × 每 city；query_chart 留空字串，
--    api_endpoint 路徑接管，不會被 controller 執行）
INSERT INTO query_charts
  (index, history_config, map_config_ids, map_filter, time_from, update_freq,
   update_freq_unit, source, short_desc, long_desc, use_case, links,
   contributors, created_at, updated_at, query_type, query_chart, city)
VALUES
  ('youbike_persistence', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內每小時平均可借車輛低於 1 的小時數最多的前 20 站。',
   '以觀測時段中每小時的平均可借車輛數作為基準，當該時段平均可借車輛低於 1 時計入該站的缺車時數，並依累計時數由高至低排序。本指標反映站點長時間處於可借車輛不足之狀態，前段排名以站柱數較少的觀光與郊區終點型站為主，係因該類站點車量上限較低、達門檻所需流出量較少。資料採用 2026/05/01 之單日快照，與線上「YouBike 見車率」之月度統計相互對照可獲得較完整之長期趨勢。',
   '輔助辨識長時間缺車之站點，作為補給班次規劃、站點規模檢討及調度資源配置之參考。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'taipei'),

  ('youbike_persistence', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內每小時平均可借車輛低於 1 的小時數最多的前 20 站。',
   '以觀測時段中每小時的平均可借車輛數作為基準，當該時段平均可借車輛低於 1 時計入該站的缺車時數，並依累計時數由高至低排序。本指標反映站點長時間處於可借車輛不足之狀態，前段排名以站柱數較少的觀光與郊區終點型站為主，係因該類站點車量上限較低、達門檻所需流出量較少。資料採用 2026/05/01 之單日快照，與線上「YouBike 見車率」之月度統計相互對照可獲得較完整之長期趨勢。',
   '輔助辨識長時間缺車之站點，作為補給班次規劃、站點規模檢討及調度資源配置之參考。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'metrotaipei'),

  ('youbike_imbalance', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內估計借出量與歸還量差距最大之前 15 站。',
   '以 30 分鐘間隔快照逐筆比對可借車輛數變化，將下降量加總作為估計借出量、上升量加總作為估計歸還量（含調度補車），兩者差值之絕對值最高者代表結構性流出顯著大於歸還之站點。歸還量並依單筆變化幅度區分為市民自然還車與調度補車。資料採用 2026/05/01 之單日快照，連續多日累積後可進一步辨識結構性需求站點。',
   '作為補車班次優先序、調度路線規劃及站點需求結構分析之輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'taipei'),

  ('youbike_imbalance', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內估計借出量與歸還量差距最大之前 15 站。',
   '以 30 分鐘間隔快照逐筆比對可借車輛數變化，將下降量加總作為估計借出量、上升量加總作為估計歸還量（含調度補車），兩者差值之絕對值最高者代表結構性流出顯著大於歸還之站點。歸還量並依單筆變化幅度區分為市民自然還車與調度補車。資料採用 2026/05/01 之單日快照，連續多日累積後可進一步辨識結構性需求站點。',
   '作為補車班次優先序、調度路線規劃及站點需求結構分析之輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'metrotaipei')
ON CONFLICT (index, city) DO UPDATE
  SET short_desc = EXCLUDED.short_desc,
      long_desc  = EXCLUDED.long_desc,
      use_case   = EXCLUDED.use_case,
      query_type = EXCLUDED.query_type,
      query_chart = EXCLUDED.query_chart,
      updated_at = NOW();

-- 5. 把 youbike-analysis-{taipei,metrotaipei} 兩個 dashboard 的 components 陣列
--    重建成 6 個 id（idempotent，重跑也只會得到同一份結果）
UPDATE dashboards
SET components = ARRAY[
  (SELECT id FROM components WHERE index = 'youbike_timemap'),
  (SELECT id FROM components WHERE index = 'youbike_availability'),
  (SELECT id FROM components WHERE index = 'youbike_persistence'),
  (SELECT id FROM components WHERE index = 'youbike_imbalance'),
  (SELECT id FROM components WHERE index = 'bike_map'),
  (SELECT id FROM components WHERE index = 'bike_network')
]::integer[],
    updated_at = NOW()
WHERE index IN ('youbike-analysis-taipei', 'youbike-analysis-metrotaipei')
  AND NOT EXISTS (
    -- 防呆：任何一個 id 找不到就不要動 dashboard，避免變成包含 NULL 的陣列。
    SELECT 1 FROM components
    WHERE index IN ('youbike_timemap','youbike_availability','youbike_persistence',
                    'youbike_imbalance','bike_map','bike_network')
    GROUP BY 1=1
    HAVING COUNT(*) < 6
  );
```

- [ ] **Step 2: 在 `scripts/load-ubike-data.sh` step 2 末追加 seed 執行**

把這段（第 60-63 行）：

```bash
# ---------- 2. Seed dashboardmanager (component + dashboard) ----------
echo "==> [2/5] Seeding ${MANAGER_DB} (timemap component + Youbike Analysis dashboard)"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-timemap-seed.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-analysis-dashboard.sql"
```

改成：

```bash
# ---------- 2. Seed dashboardmanager (component + dashboard) ----------
echo "==> [2/5] Seeding ${MANAGER_DB} (timemap + shortage blocks + Youbike Analysis dashboard)"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-timemap-seed.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-analysis-dashboard.sql"
psql_db "${MANAGER_DB}" -q < "${REPO_ROOT}/db-sample-data/youbike-shortage-blocks-seed.sql"
```

順序很重要：`youbike-shortage-blocks-seed.sql` 的 step 5 會引用 `bike_map`、`bike_network`、`youbike_availability` 這些 component（在 dashboardmanager-demo.sql 裡 seed），以及 `youbike_timemap`（在 youbike-timemap-seed.sql 裡 seed），所以這支必須在 timemap-seed 與 analysis-dashboard 之後跑。

- [ ] **Step 3: 對 dashboardmanager DB 跑新 seed 並驗證**

```bash
sudo docker exec -i postgres-manager psql -v ON_ERROR_STOP=1 -U postgres -d dashboardmanager -q < /home/winlab/Taipei-City-Dashboard/db-sample-data/youbike-shortage-blocks-seed.sql
```

Expected: 無錯（如果是初次跑會看到 INSERT 0 2、UPDATE 2；重跑時都是 0 row inserted、2 row updated）。

- [ ] **Step 4: 驗證 DB rows**

```bash
sudo docker exec -i postgres-manager psql -U postgres -d dashboardmanager -c "
SELECT cc.index, cc.types, cc.unit, cc.api_endpoint
FROM component_charts cc
WHERE cc.index IN ('youbike_persistence','youbike_imbalance');
"
```

Expected: 看到兩列，`api_endpoint` 分別是 `/commute/youbike/persistence` 和 `/commute/youbike/imbalance`。

```bash
sudo docker exec -i postgres-manager psql -U postgres -d dashboardmanager -c "
SELECT index, components FROM dashboards
WHERE index IN ('youbike-analysis-taipei','youbike-analysis-metrotaipei');
"
```

Expected: 看到兩列，`components` 各是 6 個 id 的 array。對照 `components` 表確認順序：`youbike_timemap, youbike_availability, youbike_persistence, youbike_imbalance, bike_map, bike_network`。

- [ ] **Step 5: 驗證 BE `/dashboard/{index}` 已能回 6 個 component 含 api_endpoint**

```bash
curl -s 'http://localhost:8080/api/v1/dashboard/youbike-analysis-taipei' | jq '.data | length, .data[].name, [.data[] | .chart_config.api_endpoint] | .[]'
```

Expected: `6` followed by 6 個 component name；`api_endpoint` 陣列中只有 persistence/imbalance 兩格有值，其他四格為 `null`。

- [ ] **Step 6: Commit DB seed**

```bash
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' add \
  db-sample-data/youbike-shortage-blocks-seed.sql \
  scripts/load-ubike-data.sh

git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit -m "$(cat <<'EOF'
feat(youbike-analysis): seed persistence/imbalance 為真實 component 並 splice 進 dashboard

- 新增 youbike-shortage-blocks-seed.sql (idempotent)：ALTER TABLE 加 api_endpoint、insert 兩個 component + chart + 4 個 query_chart、把兩個 dashboard 的 components 陣列重建成 6 個 id
- load-ubike-data.sh 在 step 2 多跑此 seed

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: FE — chart-data fetch 加 `api_endpoint` 分支（additive）

**Files:**
- Modify: `Taipei-City-Dashboard-FE/src/store/contentStore.js:330-369`

只動 fetch loop，把「有 `api_endpoint` 就改打那條」的判斷加進來。**不**碰 shim 相關 code，shim 在 Task 7 才清掉，這樣即使新路徑出 bug 也好回退。

- [ ] **Step 1: 改 `setCurrentDashboardAllChartData` 第一段 chart-data fetch loop**

把這段（第 330-369 行）：

```js
					const component = this.cityDashboard.components[index];
					try {
						// 4-2. Get chart data
						const response = await http.get(
							`/component/${component.id}/chart`,
							{
								params: {
									city: component.city,
									...(!["static", "current", "demo"].includes(
										component.time_from,
									)
										? getComponentDataTimeframe(
												component.time_from,
												component.time_to,
												true,
											)
										: {}),
								},
							},
						);

						this.cityDashboard.components[index].chart_data =
							response.data.data;

						if (response.data.categories) {
							this.cityDashboard.components[
								index
							].chart_config.categories =
								response.data.categories;
						}
					} catch (error) {
						console.error(
							`Failed to fetch chart data for component ${component.id}:`,
							error,
						);
						// Set empty chart data to avoid errors in subsequent operations
						this.cityDashboard.components[index].chart_data = [];

						this.loading = false;
					}
```

改成：

```js
					const component = this.cityDashboard.components[index];
					try {
						// 4-2. Get chart data — components with chart_config.api_endpoint
						// (mirror of component_maps.api_endpoint) take priority over the
						// stored SQL path, letting BE controllers serve computed metrics
						// from a different DB without faking SQL through GORM.
						const apiEndpoint = component.chart_config?.api_endpoint;
						const response = apiEndpoint
							? await http.get(apiEndpoint, {
									params: { city: component.city },
								})
							: await http.get(
									`/component/${component.id}/chart`,
									{
										params: {
											city: component.city,
											...(!["static", "current", "demo"].includes(
												component.time_from,
											)
												? getComponentDataTimeframe(
														component.time_from,
														component.time_to,
														true,
													)
												: {}),
										},
									},
								);

						this.cityDashboard.components[index].chart_data =
							response.data.data;

						if (response.data.categories) {
							this.cityDashboard.components[
								index
							].chart_config.categories =
								response.data.categories;
						}
					} catch (error) {
						console.error(
							`Failed to fetch chart data for component ${component.id}:`,
							error,
						);
						// Set empty chart data to avoid errors in subsequent operations
						this.cityDashboard.components[index].chart_data = [];

						this.loading = false;
					}
```

- [ ] **Step 2: 用瀏覽器手測 — Youbike Analysis 6 個 block 都應該畫得出來**

先確認 FE Vite dev server 在跑（`docker logs dashboard-fe --tail 5` 確認最後一行是 vite ready）。瀏覽器 hard reload `http://localhost:3000`，登入 `admin@example.com` / `Admin123!`。

側邊欄打開「臺北 → Youbike Analysis」（注意現在 SideBar 上**會同時有兩個 dashboard**：BE 的 Youbike Analysis 與舊的 client-injected「YouBike 缺車成因分析」——shim 還沒清，預期會看到兩個入口）。

點 Youbike Analysis 應該看到：
1. youbike_timemap (時間軸地圖)
2. youbike_availability (可借率)
3. **youbike_persistence (BarChart, top 20)**
4. **youbike_imbalance (BarChart, top 15)**
5. bike_map
6. bike_network

DevTools Network 面板：
- persistence component 的 chart 請求 URL 應該是 `/api/commute/youbike/persistence?city=taipei`，不是 `/api/component/{id}/chart`
- imbalance 同理

如果出現「chart 是空的」或「No chart data available」：
- 檢查 `curl 'http://localhost:8080/api/v1/commute/youbike/persistence?city=taipei' | jq` 是否仍正常
- 檢查 `console.log(component.chart_config)` 看 `api_endpoint` 有沒有正確下來
- 檢查 Network response 的 `data[0].data` 形狀

雙北版（左上切到「雙北」）一樣 6 個 block，persistence/imbalance 切換時 city 參數應該變 `metrotaipei`。

- [ ] **Step 3: 截圖留證（在計畫旁邊放 screenshot 方便 review）**

```bash
# 用任意 screenshot tool 拍 Youbike Analysis 6 個 block 的全貌
# 把檔案命名為 plan-task5-{taipei,metrotaipei}.png
```

（這步是 nice-to-have，不阻塞 commit。）

- [ ] **Step 4: Commit additive 變更**

```bash
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' add \
  Taipei-City-Dashboard-FE/src/store/contentStore.js

git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit -m "$(cat <<'EOF'
feat(youbike-analysis): FE chart-data fetch 支援 chart_config.api_endpoint

鏡像 component_maps.api_endpoint 的處理方式：當 component_charts 帶 api_endpoint 時，
chart-data fetch 改打那條 URL（只帶 city 參數），不打 /component/{id}/chart。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: FE build 驗證

至此 Vue dev server 已 hot-reload 過，但 production build 路徑（lint + Vite build）還沒驗。CI 跑這條，先在本地確認沒戳到 lint。

- [ ] **Step 1: 跑 npm run build**

```bash
cd Taipei-City-Dashboard-FE && npm run build
```

Expected: ESLint 自動修整通過、Vite build 成功，產出 `dist/`。如果 ESLint 紅，看訊息修；如果 Vite build 紅，可能是某處還引用了 `youbikeShortageBlocks` 的 export（這個 Task 5 不該動到，但保險起見）。

注意：如果 `npm run build` 觸發了非預期的 ESLint 自動修整，要 `git diff` 確認改動可接受才 commit。一般情況下 `setCurrentDashboardAllChartData` 既有風格與本次新增的 if-else 分支相容。

- [ ] **Step 2: 如有變更，amend 進前一 commit**

```bash
# 只在 ESLint 自動改了東西時做這步：
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit --amend --no-edit -a
```

否則跳過。

---

## Task 7: FE 清 shim — 刪 `youbikeShortageBlocks.js` 與相關 code

**Files:**
- Delete: `Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js`
- Modify: `Taipei-City-Dashboard-FE/src/store/contentStore.js`（5 處）
- Modify: `Taipei-City-Dashboard-FE/src/views/DashboardView.vue`（3 處）

新路徑驗證 OK 後，把舊的 client-injected dashboard 與所有 `isYoubikeShortageIndex` 守門碼一次清掉。

- [ ] **Step 1: 改 `contentStore.js` import block（第 19-24 行）**

把：

```js
import {
	YOUBIKE_SHORTAGE_DASHBOARDS,
	isYoubikeShortageIndex,
	getYoubikeShortageDashboard,
	loadYoubikeShortageComponents,
} from "./youbikeShortageBlocks";
```

整段刪掉（連同前面的空白行不變）。

- [ ] **Step 2: 改 `contentStore.js` 移除 `injectYoubikeShortageDashboard` action（第 93-104 行）**

把這段：

```js
		// Inject local YouBike 缺車分析 dashboards into each city list (idempotent).
		// 仿 production：臺北版掛 taipei 群組、雙北版掛 metrotaipei 群組。
		injectYoubikeShortageDashboard() {
			YOUBIKE_SHORTAGE_DASHBOARDS.forEach((d) => {
				const list = this.dashboards.get(d.city) ?? [];
				if (list.find((item) => item.index === d.index)) {
					return;
				}
				list.unshift({ index: d.index, name: d.name, icon: d.icon });
				this.dashboards.set(d.city, list);
			});
		},
```

整段刪掉。

- [ ] **Step 3: 改 `contentStore.js` 移除 `loadYoubikeShortageDashboard` action（第 105-127 行）**

把：

```js
		// Load a YouBike 缺車分析 dashboard from local JSON (skip BE)
		async loadYoubikeShortageDashboard(index) {
			const dashboard = getYoubikeShortageDashboard(index);
			if (!dashboard) {
				this.error = true;
				this.loading = false;
				return;
			}
			this.currentDashboard.name = dashboard.name;
			this.currentDashboard.icon = dashboard.icon;
			try {
				const components = await loadYoubikeShortageComponents(index);
				this.cityDashboard.components = components;
				this.filterCurrentDashboardContent();
			} catch (error) {
				console.error("Failed to load YouBike shortage dashboard:", error);
				this.cityDashboard.components = [];
				this.currentDashboard.components = [];
				this.currentDashboardExcluded.components = [];
				this.error = true;
			}
			this.loading = false;
		},
```

整段刪掉。

- [ ] **Step 4: 改 `contentStore.js` 移除 sidebar 注入呼叫（第 202-203 行）**

把：

```js
			// Inject local YouBike 缺車分析 dashboard into 雙北 list
			this.injectYoubikeShortageDashboard();
```

整段刪掉（連同緊接的空白行不變）。

- [ ] **Step 5: 改 `contentStore.js` 移除 `setCurrentDashboardAllContent` 內的 shortage 分支（第 262-267 行）**

把：

```js
		async setCurrentDashboardAllContent() {
			// Local injected dashboard: skip BE and load from local JSON
			if (isYoubikeShortageIndex(this.currentDashboard.index)) {
				await this.loadYoubikeShortageDashboard(this.currentDashboard.index);
				return;
			}

			const currentCityDashboards = this.currentDashboard.city
```

改成：

```js
		async setCurrentDashboardAllContent() {
			const currentCityDashboards = this.currentDashboard.city
```

- [ ] **Step 6: 改 `DashboardView.vue` 移除 import（第 18 行）**

把：

```js
import { isYoubikeShortageIndex } from "../store/youbikeShortageBlocks";
```

整行刪掉。

- [ ] **Step 7: 改 `DashboardView.vue` 第一處 favorite-btn（第 90 行）**

把：

```html
      :favorite-btn="authStore.token && !isYoubikeShortageIndex(contentStore.currentDashboard.index)"
```

改成：

```html
      :favorite-btn="authStore.token"
```

- [ ] **Step 8: 改 `DashboardView.vue` 第二處 favorite-btn（第 147-151 行）**

把：

```html
      :favorite-btn="
        authStore.token &&
          contentStore.currentDashboard.icon !== 'favorite' &&
          !isYoubikeShortageIndex(contentStore.currentDashboard.index)
      "
```

改成：

```html
      :favorite-btn="
        authStore.token &&
          contentStore.currentDashboard.icon !== 'favorite'
      "
```

- [ ] **Step 9: 刪 `youbikeShortageBlocks.js`**

```bash
rm Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js
```

- [ ] **Step 10: grep 確認沒漏網之魚**

```bash
grep -rn "youbikeShortageBlocks\|isYoubikeShortageIndex\|YOUBIKE_SHORTAGE_DASHBOARDS\|getYoubikeShortageDashboard\|loadYoubikeShortageComponents\|loadYoubikeShortageDashboard\|injectYoubikeShortageDashboard" Taipei-City-Dashboard-FE/src/
```

Expected: 無任何輸出。如果有殘留就把對應檔案再清乾淨。

- [ ] **Step 11: build 驗證**

```bash
cd Taipei-City-Dashboard-FE && npm run build
```

Expected: lint + build 都通過。

- [ ] **Step 12: 瀏覽器手測**

- 重新整理瀏覽器 → 登入。
- 側邊欄「臺北 → Youbike Analysis」：仍 6 個 block，行為正常。
- 側邊欄**不應**再出現「YouBike 缺車成因分析」分頁。
- 把 URL 直接改成 `?index=youbike-shortage-analysis-taipei&city=taipei`：應該被 fallback 導去「第一個可用 dashboard」（如果原 query string 完全不認得，看 `setCurrentDashboardAllContent` 第 277-298 行的處理）。
- 收藏按鈕：6 個 component 上都應該看得到（沒 `synthetic` / `isYoubikeShortageIndex` 過濾）。

- [ ] **Step 13: Commit FE 清理**

```bash
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' add \
  Taipei-City-Dashboard-FE/src/store/contentStore.js \
  Taipei-City-Dashboard-FE/src/views/DashboardView.vue \
  Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js

git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit -m "$(cat <<'EOF'
refactor(youbike-analysis): 拿掉客戶端注入 shim，全走 BE chart-data 路徑

persistence/imbalance 已是 BE 真實 component（id 由 dashboardmanager DB 管理），
不再需要 youbikeShortageBlocks.js 的 client-injected dashboard、
isYoubikeShortageIndex 守門、與 contentStore 內的 special branch。

- 刪 src/store/youbikeShortageBlocks.js
- contentStore: 移 import / injectYoubikeShortageDashboard / loadYoubikeShortageDashboard / setCurrentDashboardAllContent 的 shortage 分支
- DashboardView: favorite-btn 兩處不再過濾 isYoubikeShortageIndex

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 文件更新

**Files:**
- Modify: `STORY-youbike-shortage-dashboard.md`
- Modify: `CLAUDE.md`
- Modify: `Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go:78`（註解指向）

- [ ] **Step 1: 更新 `STORY-youbike-shortage-dashboard.md` 開頭段落**

打開檔案，把現有第 1-9 行：

```markdown
# YouBike 缺車成因分析 — Dashboard 說故事手冊

> 此文件描述「YouBike 缺車成因分析」儀表板要呈現的 user story，以及兩個重點 block 背後的資料做法。對應程式碼位於：
> - 後端聚合：`Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go`
> - 後端路由：`Taipei-City-Dashboard-BE/app/controllers/commute.go` (`GetYouBikeShortageAnalysis`)
> - 前端組裝：`Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js`
```

改成：

```markdown
# YouBike 缺車成因分析 — Dashboard 說故事手冊

> 此文件描述「YouBike 缺車成因分析」要呈現的 user story，以及兩個重點 block 背後的資料做法。
>
> **整合狀態（2026-05-03）**：兩個重點 block 已併入 `youbike-analysis-{taipei,metrotaipei}` dashboard 作為真實 BE component；舊的純前端 `youbike-shortage-analysis-*` 入口已收掉。Block 1（rhythm）與 Block 4（heatmap）兩個輔助 block 已停用，但 `aggregate.go` 仍保留計算待後續瘦身。對應程式碼：
> - 後端聚合：`Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go`
> - 後端路由：`Taipei-City-Dashboard-BE/app/controllers/commute.go`（`GetYouBikePersistenceChart`、`GetYouBikeImbalanceChart`，舊的 `GetYouBikeShortageAnalysis` 也保留）
> - DB seed：`db-sample-data/youbike-shortage-blocks-seed.sql`
```

- [ ] **Step 2: 更新 `STORY-youbike-shortage-dashboard.md` 資料流圖**

```bash
grep -n "youbike-shortage-analysis\|GET /api/v1/commute/youbike/shortage-analysis" STORY-youbike-shortage-dashboard.md
```

對找到的每行做替換（用 sed 或 Edit）：

- 把 `GET /api/v1/commute/youbike/shortage-analysis` 改成 `GET /api/v1/commute/youbike/{persistence,imbalance}`
- 把 `youbike-shortage-analysis-{taipei,metrotaipei}` 改成 `youbike-analysis-{taipei,metrotaipei}`

如果手動逐行找會 miss，可以開檔案 review 整段「資料流」與「前端組裝」章節並改寫。**不要**改主敘事章節（block 1/2 的內容描述）。

- [ ] **Step 3: 更新 `CLAUDE.md` 加上 `component_charts.api_endpoint` 規約段**

打開 `CLAUDE.md`，找到「### Map Layer Source Types」這段（裡面講 `component_maps.source` 的三種類型）。在這段後面追加新的小節：

```markdown
### Chart Data Source Types

`component_charts.api_endpoint` controls how `contentStore.setCurrentDashboardAllChartData()` fetches chart data:

| `api_endpoint` value | Behavior |
|---|---|
| `null` (default) | Fetches `/component/{id}/chart` (executes `query_charts.query_chart` SQL against DBDashboard) |
| `/commute/...` | Fetches that URL with `?city=...` query (BE controller serves computed metrics, e.g. cross-DB aggregates) |

Mirrors the `component_maps.api_endpoint` pattern used by `youbike_timemap`. URL convention: chart `api_endpoint` does **not** include the `/api` prefix (FE uses the `http` Axios instance whose `baseURL` already prepends `/api`); map `api_endpoint` does include `/api` (FE uses raw `axios`). The two will be unified in a future refactor.

The `api_endpoint` column was added via `ALTER TABLE component_charts ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR;` (in `youbike-shortage-blocks-seed.sql`).
```

- [ ] **Step 4: 更新 `CLAUDE.md` 的「Implemented Features」區塊**

找到 "### YouBike 一日可用率動態地圖" 這個小節之後，追加一個新小節（在「## Key Conventions」之前）：

```markdown
### YouBike 缺車成因 — persistence / imbalance（branch: `feat/youbike-shortage-dashboard`）

兩個分析 block 併入「Youbike Analysis」dashboard：`youbike_persistence`（長時段缺車站排行）與 `youbike_imbalance`（站點淨流出量排行）。走 `component_charts.api_endpoint` 規約讓 chart-data fetch 從 `/commute/youbike/persistence` 與 `/commute/youbike/imbalance` 取資料，BE 內部 reuse `aggregate.Run()` cache。

**Files changed:**

| File | Change |
|------|--------|
| `Taipei-City-Dashboard-BE/app/models/componentConfig.go` | `ComponentChart` 加 `ApiEndpoint *string` 欄位 |
| `Taipei-City-Dashboard-BE/app/controllers/commute.go` | 抽 `getYouBikeAggregatePayload` helper；新增 `GetYouBikePersistenceChart`、`GetYouBikeImbalanceChart` |
| `Taipei-City-Dashboard-BE/app/routes/router.go` | 註冊 `/commute/youbike/{persistence,imbalance}` |
| `db-sample-data/youbike-shortage-blocks-seed.sql` | idempotent seed：ALTER TABLE 加 api_endpoint、insert 兩個 component + chart + 4 個 query_chart、把兩 dashboard 的 `components` 重建成 6 個 id |
| `scripts/load-ubike-data.sh` | step 2 多跑此 seed |
| `Taipei-City-Dashboard-FE/src/store/contentStore.js` | chart-data fetch 看到 `chart_config.api_endpoint` 就改打該 URL；移除 youbikeShortageBlocks shim 相關所有分支 |
| `Taipei-City-Dashboard-FE/src/views/DashboardView.vue` | 兩處 favorite-btn 不再過濾 `isYoubikeShortageIndex`，import 移除 |
| `Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js` | **刪除** |

**API endpoints:**

```
GET /api/v1/commute/youbike/persistence?city=taipei|metrotaipei
  → { status, data: [{name, data: [{x: station, y: empty_hours}, ...]}], categories: [...] } (top 20)

GET /api/v1/commute/youbike/imbalance?city=taipei|metrotaipei
  → { status, data: [{name, data: [{x: station, y: -imbalance}, ...]}], categories: [...] } (top 15)
```

**遺留**：`aggregate.go` 仍計算 rhythm 與 heatmap 兩段（沒人讀）；`/commute/youbike/shortage-analysis` 路由保留。下個 PR 再瘦身。
```

- [ ] **Step 5: 改 `aggregate.go:78` 的註解指向**

把這行（第 78 行）：

```go
// frontend actually reads (see Taipei-City-Dashboard-FE/src/store/youbikeShortageBlocks.js).
```

改成：

```go
// frontend actually reads (see controllers/commute.go's GetYouBikePersistenceChart
// and GetYouBikeImbalanceChart — rhythm and heatmap blocks are computed but no
// longer surfaced to the dashboard, pending a follow-up PR that slims this down).
```

- [ ] **Step 6: Commit 文件變更**

```bash
git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' add \
  STORY-youbike-shortage-dashboard.md \
  CLAUDE.md \
  Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go

git -c user.name='Tim Kuo' -c user.email='me@timkuo.dev' commit -m "$(cat <<'EOF'
docs(youbike-analysis): 更新 STORY、CLAUDE.md 與 aggregate.go 註解指向新整合架構

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: 端到端最終驗證

跑一輪「乾淨環境」流程，模擬新人 clone 完照 CLAUDE.md 走的體驗，確認 seed / build / endpoint / FE 都串得起來。

- [ ] **Step 1: 重啟 BE**

```bash
sudo docker restart dashboard-be
sleep 5
sudo docker logs dashboard-be --tail 20
```

Expected: 看到 Gin 起來、無 panic。

- [ ] **Step 2: 對 4 個 endpoint 各跑一次 curl**

```bash
for ep in persistence imbalance; do
  for city in taipei metrotaipei; do
    echo "=== /commute/youbike/$ep?city=$city ==="
    curl -s "http://localhost:8080/api/v1/commute/youbike/$ep?city=$city" \
      | jq '{status, name: .data[0].name, n: (.data[0].data | length), first: .data[0].data[0], last: .data[0].data[-1]}'
  done
done
```

Expected: 4 組輸出都 `status: success`、`n` 為 20 或 15、`first`/`last` 結構是 `{x, y}`。

- [ ] **Step 3: 對 dashboard 端點驗 6 個 component**

```bash
for idx in youbike-analysis-taipei youbike-analysis-metrotaipei; do
  echo "=== /dashboard/$idx ==="
  curl -s "http://localhost:8080/api/v1/dashboard/$idx" \
    | jq '{n: (.data | length), names: [.data[].name], api_endpoints: [.data[].chart_config.api_endpoint]}'
done
```

Expected: `n: 6`，`names` 含 `youbike_timemap` 等 6 個（依 seed 順序），`api_endpoints` 中只有 persistence/imbalance 兩格非 null。

- [ ] **Step 4: 瀏覽器手測 + 截圖**

打開 http://localhost:3000 → 登入 → 臺北 → Youbike Analysis → 截圖。
切到雙北 → Youbike Analysis → 截圖。
側邊欄滑一遍 → 確認**不再**有「YouBike 缺車成因分析」入口。
任意點一個 component 的「★ 收藏」 → 確認可以加入收藏。

- [ ] **Step 5: 跑 npm build + go build 雙重 sanity**

```bash
(cd Taipei-City-Dashboard-FE && npm run build) && (cd Taipei-City-Dashboard-BE && go build -v ./...)
```

Expected: 兩段都成功。

- [ ] **Step 6: 最後檢查 git history**

```bash
git log --oneline origin/feat/youbike-shortage-dashboard..HEAD
```

Expected: 看到 5 條 commit（spec rewrite + Task 3/4/5/7/8 共 5 個 feat/refactor/docs commit）。如果想再壓 commit 留給用戶決定，**不要**自己 force-push 或 amend 既有 commit。

---

## Self-Review

**Spec coverage:**

| Spec 條目 | 對應 Task |
|---|---|
| `ComponentChart` 加 `ApiEndpoint` 欄位 | Task 1 |
| BE 兩個新 controller (persistence / imbalance) | Task 2 (helper) + Task 3 |
| 路由註冊 | Task 3 step 4 |
| `youbike-shortage-blocks-seed.sql`（schema + components + dashboard 重建） | Task 4 |
| `load-ubike-data.sh` 整合 | Task 4 step 2 |
| FE chart-data fetch 加 api_endpoint 分支 | Task 5 |
| FE 移除 shim（contentStore + DashboardView + 刪檔） | Task 7 |
| `STORY-youbike-shortage-dashboard.md` 更新 | Task 8 step 1-2 |
| `CLAUDE.md` 加 `component_charts.api_endpoint` 規約 | Task 8 step 3-4 |
| `aggregate.go` 註解指向 | Task 8 step 5 |
| 失敗處理（每 component 獨立 fetch、不影響他人） | Task 5 既有 catch 已涵蓋；Task 9 step 4 用瀏覽器驗 |
| Cache 共用 | Task 2 把 cache 抽進 helper，三個 endpoint 共用 |

**Placeholder scan:** 無 TBD / TODO / "implement later"。Task 4 的 SQL 一字不漏完整可跑，Task 5 的 JS diff 一字不漏完整可貼，Task 7 的 9 個 step 各列出明確要刪/改的行區。

**Type consistency:** 
- BE: `chartTwoDimResponse` / `chartTwoDimSeries` / `chartTwoDimPoint` 三個 type 在 Task 3 step 1 一次定義，Task 3 step 2、3 兩個 controller 用的是同一組 type。
- BE: `getYouBikeAggregatePayload` 簽名（`(youbike_aggregate.Payload, int, string)`）在 Task 2 step 1 定義，Task 2 step 2 與 Task 3 step 2、3 三處 caller 都用相同形狀拆包。
- FE: `chart_config?.api_endpoint` 在 Task 5 step 1 是讀取點，Task 4 step 1 在 DB 寫入此欄位，BE Task 1 在 `ComponentChart.ApiEndpoint` 對齊欄位 JSON 名 `api_endpoint`。三邊一致。
- DB: `dashboards.components` 重建順序與 `youbike-analysis-dashboard.sql` 既有 components 欄位的 4 個 id 對齊（用 index lookup 而非寫死 id）。

**Scope check:** 一個 PR 範圍：BE schema/controller/route + DB seed + FE wiring + FE cleanup + 文件。不切割，整合度高。獨立其實也行（BE 為一 PR、FE 為另一 PR），但目前 hackathon mode 偏好單一 PR；這份計畫 commit 序列已經分成 5 個邏輯單位，有需要可以分批 cherry-pick。

---

**計畫完成，存於 `docs/superpowers/plans/2026-05-03-merge-shortage-into-youbike-analysis.md`。兩種執行選項：**

**1. Subagent-Driven（推薦）** — 每個 task dispatch 新 subagent，task 之間我 review，迭代快  
**2. Inline Execution** — 在這個 session 走 executing-plans，分批 checkpoint review

選哪個？
