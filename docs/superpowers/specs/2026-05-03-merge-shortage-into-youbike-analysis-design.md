# 將「YouBike 缺車成因分析」整合進「Youbike Analysis」— 設計

## 目標

把現行純前端注入的 `youbike-shortage-analysis-{taipei,metrotaipei}` dashboard 收掉，將其中**只**保留兩個敘事核心 block——`youbike_persistence`（長時段缺車站排行）與 `youbike_imbalance`（站點淨流出量排行）——以「**真實 BE component**」身份併入既有的 `youbike-analysis-{taipei,metrotaipei}` dashboard。Block 1 (`youbike_rhythm`) 與 Block 4 (`youbike_heatmap`) 不再呈現。

「真實 BE component」表示：兩個 block 在 `components` / `component_charts` / `query_charts` 都有真實的 row，FE 走標準 chart-data 流程取資料，**不再有 `synthetic` 旗標、不再有客戶端注入分支**。

## 設計選擇

採用 **api\_endpoint 鏡像 map 模式**：在 `component_charts` 增加 `api_endpoint VARCHAR` 欄位，鏡像 `component_maps.api_endpoint` 的既有規約。FE 在 chart-data fetch loop 看到 `chart_config.api_endpoint` 就改打那條 URL，不打 `/component/{id}/chart`。BE 新增兩條 thin endpoint，內部 reuse `aggregate.Run()` cache，回傳標準 chart-data 形狀。

選此方案的理由：

1. 跟 `youbike_timemap` 的 `component_maps.api_endpoint` 規約完全一致，引入零個新概念。
2. 兩個 block 在 `/component/` 列表、admin UI、Qdrant 索引、未來收藏等流程都自動成為 first-class citizen，未來維護者打開 dashboard 看到 6 個 component 都能用標準路徑追到資料來源。
3. 複雜計算（dispatch\_dependency 拆「自然還車 vs 補車」等）保留在 Go `aggregate.go`，不必硬翻成跨 DB SQL。

代價：BE chart-data 路徑會有兩條（`query_charts.query_chart` SQL 路徑 + `chart_config.api_endpoint` 路徑），但分支已經存在於 map 那邊，不算新增成本。

## 不在範圍

- **不**對 `aggregate.go` 瘦身。雖然之後 rhythm 與 heatmap 不再被前端讀，仍保留計算邏輯與 cache 結構不動，避免 PR scope 失控；下個 PR 再清。對應地 `/commute/youbike/shortage-analysis` 這條 endpoint 也保留（現在沒人讀）。
- **不**改既有 4 個 BE component 的 chart_config 或 query_charts。
- **不**處理舊 URL `?index=youbike-shortage-analysis-*` 的相容跳轉，走既有 `setCurrentDashboardAllContent` fallback 路徑（找不到就導去第一個可用 dashboard）。

## 元件序

整合後 `youbike-analysis-{taipei,metrotaipei}` 的 `components` 陣列：

| 順序 | id | index | 來源 |
|---|---|---|---|
| 1 | 1   | `youbike_timemap`     | BE（既有） |
| 2 | 60  | `youbike_availability`| BE（既有） |
| 3 | **TBD-A** | **`youbike_persistence`** | BE（新增，api\_endpoint 路徑） |
| 4 | **TBD-B** | **`youbike_imbalance`**   | BE（新增，api\_endpoint 路徑） |
| 5 | 217 | `bike_map`            | BE（既有） |
| 6 | 213 | `bike_network`        | BE（既有） |

新增的兩個 component id 由 `components` 表序列分配，不寫死；seed SQL 用 `INSERT ... RETURNING id` 抓回再寫進 `dashboards.components` 陣列。

## 架構

### 資料流

```
SideBar tab "Youbike Analysis" (taipei or metrotaipei)
    │
    ▼
contentStore.setCurrentDashboardAllContent
    │
    ├─ GET /api/v1/dashboard/youbike-analysis-{taipei|metrotaipei}
    │       → 6 components（含新增 2 個，chart_config.api_endpoint 帶值）
    │
    └─ setCurrentDashboardAllChartData() — 對每個 component:
          if (chart_config.api_endpoint) {
              http.get(chart_config.api_endpoint, { params: { city } })
              → 把 response.data → component.chart_data
              → if response.categories → component.chart_config.categories
          } else {
              http.get(`/component/${id}/chart`, { params: { city, time... } })
          }
```

### 變更清單

#### Backend（Taipei-City-Dashboard-BE）

| 檔案 | 變更 |
|---|---|
| `app/models/componentConfig.go` | `ComponentChart` struct 加上 `ApiEndpoint *string \`json:"api_endpoint" gorm:"column:api_endpoint;type:varchar"\``。 |
| `app/controllers/commute.go` | 新增 `GetYouBikePersistenceChart`、`GetYouBikeImbalanceChart`。各自 reuse `aggregate.Run()`，依 `?city=taipei|metrotaipei` 對應 dataset key (`Taipei` / `All`)，回傳標準 chart-data 形狀（見下節）。 |
| `app/routes/router.go` | `configureCommuteRoutes` 增加 `/youbike/persistence`、`/youbike/imbalance` 路由（公開、跟 `/youbike/map` 同層）。 |

`/commute/youbike/shortage-analysis` 路由與 controller 保留不動（dead 但無害）；下個 PR 再瘦身。

#### Database seed（dashboardmanager DB）

新增 `db-sample-data/youbike-shortage-blocks-seed.sql`（idempotent，可重跑），內容：

1. `ALTER TABLE component_charts ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR;`
2. `INSERT INTO component_charts` 兩列：
   - `youbike_persistence`: types `{BarChart}`, color `{"#ff6b6b"}`, unit `小時`, api\_endpoint `/commute/youbike/persistence`
   - `youbike_imbalance`:  types `{BarChart}`, color `{"#fb7185"}`, unit `輛`, api\_endpoint `/commute/youbike/imbalance`
3. `INSERT INTO components` 兩列（用 `RETURNING id` 拿到分配的 id 做後續 step 用）。
4. `INSERT INTO query_charts` 各兩列（taipei、metrotaipei），`query_type='two_d'`、`query_chart=''`（不會被執行，`api_endpoint` 接管）、其餘元數據（source/short\_desc/long\_desc/use\_case）沿用前端目前文案，移除既有的動態 `tierCounts` 提示與動態 `hours_observed` 提示，改成靜態文案。
5. 兩個 component 的 id 寫進 `dashboards.youbike-analysis-{taipei,metrotaipei}.components`，依「元件序」表的位置 splice 進現有陣列：`{1, 60, <new persistence>, <new imbalance>, 217, 213}`。

`scripts/load-ubike-data.sh` 增加一行 `psql ... -f $DASHBOARD_MANAGER_SEED_DIR/youbike-shortage-blocks-seed.sql`，讓乾淨環境的 bootstrap 一次到位。

#### Frontend（Taipei-City-Dashboard-FE）

| 檔案 | 變更 |
|---|---|
| `src/store/contentStore.js` | 拿掉所有 `injectYoubikeShortageDashboard` / `loadYoubikeShortageDashboard` / `isYoubikeShortageIndex` 分支與 import。`setCurrentDashboardAllChartData` 的 for-loop 內把「呼叫 `/component/{id}/chart`」抽成「先看 `component.chart_config?.api_endpoint`，有就 `http.get(api_endpoint, { params: { city } })`，沒有就走原本路徑」。response shape 兩條路徑相同（`{ data, categories? }`），下游處理不變。 |
| `src/views/DashboardView.vue` | 拿掉 `isYoubikeShortageIndex` import 與兩處 `:favorite-btn` 內的條件——既然已經是真實 BE component，favorite 行為走預設即可。 |
| `src/store/youbikeShortageBlocks.js` | **整檔刪除。** |
| `Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go`（註解） | 第 78 行那條註解 `// frontend actually reads (see ... youbikeShortageBlocks.js)` 改指向新的 commute controller。 |

#### 文件

| 檔案 | 變更 |
|---|---|
| `STORY-youbike-shortage-dashboard.md` | 標題保留（敘事仍以「缺車成因」為主軸）。第 1 段加註：blocks 已併入 `youbike-analysis-*` dashboard，rhythm/heatmap 兩個輔助 block 已停用（aggregate.go 仍保留計算待瘦身）。資料流圖中 `/commute/youbike/shortage-analysis` 改為 `/commute/youbike/persistence` 與 `/commute/youbike/imbalance` 兩條，dashboard tab 名改為 `youbike-analysis-*`。 |
| `CLAUDE.md` | "Implemented Features" 區塊已記載 timemap，加上一段說明 `component_charts.api_endpoint` 規約：與 `component_maps.api_endpoint` 同模式，FE 在 chart-data fetch 看到此欄位就改打該 URL；URL 約定不含 `/api` 前綴（用 `http` instance fetch，baseURL 已有 `/api`）。 |

### Endpoint 形狀

`GET /api/v1/commute/youbike/persistence?city=taipei|metrotaipei`

```json
{
  "status": "success",
  "data": [
    {
      "name": "缺車時數（小時）",
      "data": [
        { "x": "中正紀念堂(3號出口)", "y": 18 },
        { "x": "捷運大直站(2號出口)", "y": 17 },
        ...
      ]
    }
  ],
  "categories": ["中正紀念堂(3號出口)", "捷運大直站(2號出口)", ...]
}
```

`GET /api/v1/commute/youbike/imbalance?city=taipei|metrotaipei` — 同形狀，`name` = `"估計淨流出量"`、`y` = `-imbalance`（保留現行符號慣例：流出為正），`data` / `categories` 取前 15 站。

兩條 endpoint 對應 city query：

| `?city=` 值 | 用 `aggregate.Run()` 哪個切片 |
|---|---|
| `taipei` (預設) | `Taipei` |
| `metrotaipei` | `All`（雙北合計） |

回傳形狀對齊 BE `componentData.go` 的 `three_d` 結構（top-level `data` + `categories`），讓 FE 既有 `setCurrentDashboardAllChartData` 對 `response.data.categories` 的處理可直接套用。

### Schema migration

`component_charts.api_endpoint` 用 `ADD COLUMN IF NOT EXISTS` 在 seed SQL 內 idempotent 加。GORM `AutoMigrate(&ComponentChart{}, ...)` 也會自動補欄位（`models/database.go:153`），但 seed 已先處理，效果一致。

### 失敗處理

`/commute/youbike/persistence` 或 `/imbalance` 請求失敗：走 `setCurrentDashboardAllChartData` 既有 catch（line 360-369），把 `chart_data` 設成空陣列、log 錯誤、不影響其他 component。**這比舊版好**——舊版聚合 API 失敗會把 4 個 block 一起變空；現在每個 component 獨立 fetch，影響範圍縮到 1 個。

### 回應 cache

`aggregate.Run()` 既有 LRU cache（看 `aggregate.go`），兩條新 endpoint 共用同一份 cache，重複 fetch 不會重算。Cache key 含 city，`taipei` 與 `metrotaipei` 兩個 city dashboard 開啟時最多算一次（雙北切片永遠包含 Taipei 切片所需資料）。

## 驗證步驟

1. 對 dashboardmanager DB 跑新 seed，確認：
   - `component_charts` 兩列存在、`api_endpoint` 有值
   - `components` 兩列存在、id 拿得到
   - `dashboards.youbike-analysis-{taipei,metrotaipei}.components` 已 splice 6 個 id 在正確位置
2. `docker restart dashboard-be`（BE 有改 Go），FE dev server。
3. 直接打 endpoint 驗證：
   ```
   curl 'http://localhost:8080/api/v1/commute/youbike/persistence?city=taipei' | jq
   curl 'http://localhost:8080/api/v1/commute/youbike/imbalance?city=metrotaipei' | jq
   ```
   兩條都應回 `{status: success, data: [{name, data: [{x, y}, ...]}], categories: [...]}`。
4. 進入 SideBar → 臺北 → **Youbike Analysis**：應依序看到 6 個 component（timemap、availability、persistence、imbalance、bike\_map、bike\_network）。雙北版（metrotaipei）同樣 6 個。
5. SideBar **不應**再有「YouBike 缺車成因分析」分頁。
6. 打開瀏覽器 DevTools Network：persistence/imbalance 兩個 component 的 request URL 應分別命中 `/api/commute/youbike/persistence` 與 `/api/commute/youbike/imbalance`，**不**是 `/component/{id}/chart`。
7. 收藏按鈕在 6 個 component 上都應出現（無 `synthetic` 過濾）。實際打 favorite endpoint 對新增的兩個 component 不在本 PR 範圍驗證——如要驗，要加進「我的最愛」dashboard 並重整看 chart_data fetch 是否仍正常（會走 api\_endpoint）。

## TODO（不在本 PR）

- 瘦身 `aggregate.go`：移除 rhythm 與 heatmap 區段、刪除 `/commute/youbike/shortage-analysis` 路由。
- 把 BE 的 `component_maps.api_endpoint` 與 `component_charts.api_endpoint` 兩處 URL 規約統一（前者目前帶 `/api` 前綴、後者不帶）。
