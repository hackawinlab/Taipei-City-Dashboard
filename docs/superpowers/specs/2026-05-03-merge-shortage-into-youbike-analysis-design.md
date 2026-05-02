# 將「YouBike 缺車成因分析」整合進「Youbike Analysis」— 設計

## 目標

把現行純前端的 `youbike-shortage-analysis-{taipei,metrotaipei}` dashboard 收掉，將其中**只**保留兩個敘事核心 block——`youbike_persistence`（長時段缺車站排行）與 `youbike_imbalance`（站點淨流出量排行）——併進已存在於 BE 的 `youbike-analysis-{taipei,metrotaipei}` dashboard。Block 1 (`youbike_rhythm`) 與 Block 4 (`youbike_heatmap`) 不再呈現。

## 範圍與不在範圍

**做這些：**

- 「Youbike Analysis」dashboard 在 SideBar 不變，但內容變成 6 個 component。
- 兩個被保留的 block 仍由 `/commute/youbike/shortage-analysis` 聚合 API 提供 chart\_data，前端組裝（不寫進 dashboardmanager DB）。
- 拿掉 SideBar 上的「YouBike 缺車成因分析」分頁。
- favorite 按鈕的「該 dashboard 不可加入收藏」邏輯，改成「該『component』不可加入收藏」（因為現在 dashboard 是真實 BE dashboard，BE 既有 4 個 component 仍應可收藏；只有兩個合成 block 不能）。

**不做這些：**

- 不把這兩個 block seed 進 BE `components` / `component_charts` / `query_charts`（這需要 dashboardmanager DB schema 變更與 chart-data 端點重作，hackathon 階段不必要）。
- 不動 `/commute/youbike/shortage-analysis` 後端 API 的回傳結構（仍會回傳 `bar_persistence`、`imbalance`、`timeline_low`、`heatmap` 四塊；前端改成只取兩塊即可，BE 留給未來其他用途）。
- 不動 `STORY-youbike-shortage-dashboard.md` 既有敘事內容（兩個保留的 block 本就是該文件強調的「兩個 block」）；只更新指引段落，把 dashboard index 改成 `youbike-analysis-*`，並註記 block 1/4 已停用。

## 元件序

「Youbike Analysis」整合後的 component 順序（user pick 過的 (b) 排法）：

1. `youbike_timemap`（id=1，BE）
2. `youbike_availability`（id=60，BE）
3. **`youbike_persistence`（id=9002，合成）** ← 新增
4. **`youbike_imbalance`（id=9004，合成）** ← 新增
5. `bike_map`（id=217，BE）
6. `bike_network`（id=213，BE）

排序語意：先看「整體現象」（時間軸地圖、可借率），再看「站點細節」（排行、淨流出），最後看「網路結構」（地圖、網路圖）。

## 架構

### 資料流

```
SideBar tab "Youbike Analysis" (taipei or metrotaipei)
    │
    ▼
contentStore.setCurrentDashboardAllContent(index = "youbike-analysis-*")
    │
    ├─ GET /api/v1/dashboard/youbike-analysis-{taipei|metrotaipei}
    │       → 4 BE components (timemap, availability, bike_map, bike_network)
    │
    ├─ if isYoubikeAnalysisIndex(index):
    │      loadYoubikeShortageBlocks(index)
    │       → GET /api/v1/commute/youbike/shortage-analysis
    │       → 取 bar_persistence + imbalance 兩塊，組成 [9002, 9004] 兩個合成 component
    │      splice 進 cityDashboard.components position 2
    │
    └─ setCurrentDashboardAllChartData()
           skip components with `synthetic === true`（chart_data 已預先填好）
```

### 變更清單（檔案層級）

| 檔案 | 變更 |
|---|---|
| `src/store/youbikeShortageBlocks.js` | 拿掉 `YOUBIKE_SHORTAGE_DASHBOARDS`、`isYoubikeShortageIndex`、`getYoubikeShortageDashboard`、Block 1/4 與 dataset 解析（`timeline_low`、`heatmap`）。新增 `isYoubikeAnalysisIndex(index)` 與 `loadYoubikeShortageBlocks(dashboardIndex)`，後者吃 `youbike-analysis-{taipei,metrotaipei}`，回傳 2 個合成 component（每個帶 `synthetic: true`）。 |
| `src/store/contentStore.js` | 拿掉 `injectYoubikeShortageDashboard`、`loadYoubikeShortageDashboard`、`isYoubikeShortageIndex` 分支。改為在 `setCurrentDashboardAllContent` 取得 BE response 之後、`filterCurrentDashboardContent` 之前，若 `isYoubikeAnalysisIndex(index)` 為真就 splice 兩個合成 block 進去 position 2。`setCurrentDashboardAllChartData` 在迴圈內 `continue` 跳過 `component.synthetic === true` 的元件。 |
| `src/views/DashboardView.vue` | 兩處 `:favorite-btn` 由 `!isYoubikeShortageIndex(contentStore.currentDashboard.index)` 改為 `!item.synthetic`。拿掉 `isYoubikeShortageIndex` import。 |
| `STORY-youbike-shortage-dashboard.md` | 文件首段加註：blocks 已併入 `youbike-analysis-*`；資料流圖中 `youbike-shortage-analysis-*` 改為 `youbike-analysis-*`；提到 Block 1（rhythm）與 Block 4（heatmap）已停用、`/commute/youbike/shortage-analysis` 仍提供完整 4 段資料但前端目前只取兩段。 |
| `Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go` | 該檔目前有一行註解 `// frontend actually reads (see ... youbikeShortageBlocks.js)`；保留，只把指向更新（檔名沒變，仍指 `youbikeShortageBlocks.js`，不需動）。實際上**不動**這支 BE 檔。 |

### 合成 component 的 favorite 行為

`isYoubikeShortageIndex(index)` 原本的用意是：「這些 dashboard 是純前端注入的，favorite 端點 BE 不認識，整個 dashboard 都別讓使用者按收藏」。

整合後：dashboard 本身是真實 BE dashboard，但裡頭混了 2 個合成 component。原本的 dashboard-level 守門變成過嚴（會把 BE 的 4 個 component 一起鎖住）。改成在每個 `<DashboardComponent>` 上以 `!item.synthetic` 判斷，讓 BE 的 4 個 component 仍可收藏，只有合成的 2 個不能。

### chart-data fetch 跳過

`setCurrentDashboardAllChartData` 是個 for-loop，會對每個 `cityDashboard.components` 的元件 call `/component/{id}/chart`。合成元件 id 是 9002、9004，BE 沒這兩筆，會 404。對應修法：迴圈裡判斷 `if (component.synthetic) continue;`。它們的 `chart_data` 已經在 `loadYoubikeShortageBlocks` 階段填好。

## 邊界 / 失敗處理

- `/commute/youbike/shortage-analysis` 失敗：目前 `loadYoubikeShortageDashboard` 會把 `currentDashboard.components` 設成空。整合後我們在 BE response 已成功之後才呼叫聚合 API；若聚合 API 失敗，**只 swallow + log，不影響 BE 4 個 component 顯示**——使用者至少看得到原本的 Youbike Analysis。實作上以 try/catch 包住 `loadYoubikeShortageBlocks` 並讓 splice 步驟略過。
- 沒登入的使用者：原本就走得到 `youbike-analysis-*`，行為不變。

## 驗證步驟

1. `docker restart dashboard-be`（如有改 BE，本案沒改可省略）+ FE 走 dev mode。
2. 進入 SideBar → 臺北 → **Youbike Analysis**：應依序看到 6 個 component（timemap、availability、persistence、imbalance、bike\_map、bike\_network）。
3. SideBar **不應**再有「YouBike 缺車成因分析」分頁。
4. 直接以 query string 走舊 URL `?index=youbike-shortage-analysis-taipei&city=taipei`：應 fallback 到第一個可用 dashboard（`setCurrentDashboardAllContent` 在找不到 currentDashboardInfo 時的既有行為）。
5. 收藏按鈕：在 `youbike-analysis-*` 下，BE 的 4 個 component 收藏按鈕**可見**；合成的 persistence、imbalance 兩個收藏按鈕**不可見**。
6. 雙北版（metrotaipei）：persistence 與 imbalance 應顯示 All（雙北合計）資料，且其 city 下拉可切到 Taipei single slice。
