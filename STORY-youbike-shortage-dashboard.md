# YouBike 缺車成因分析 — Dashboard 說故事手冊

> 此文件描述「YouBike 缺車成因分析」要呈現的 user story，以及兩個重點 block 背後的資料做法。
>
> **整合狀態（2026-05-03）**：兩個重點 block 已併入 `youbike-analysis-{taipei,metrotaipei}` dashboard 作為真實 BE component；舊的純前端 `youbike-shortage-analysis-*` 入口已收掉。Block 1（rhythm）與 Block 4（heatmap）兩個輔助 block 已停用，但 `aggregate.go` 仍保留計算待後續瘦身。對應程式碼：
> - 後端聚合：`Taipei-City-Dashboard-BE/app/youbike_aggregate/aggregate.go`
> - 後端路由：`Taipei-City-Dashboard-BE/app/controllers/commute.go`（`GetYouBikePersistenceChart`、`GetYouBikeImbalanceChart`，舊的 `GetYouBikeShortageAnalysis` 也保留）
> - DB seed：`db-sample-data/youbike-shortage-blocks-seed.sql`

---

## 一、主軸 user story

**角色**：YouBike 調度規劃人員 / 場站需求分析師

**痛點**：缺車現象天天發生，但「哪裡常缺」與「為什麼缺」常被混為一談——
有些站是長期需求大、再怎麼補都不夠；有些站是補車班次跟不上節奏；
而調度資源有限，必須先弄清楚「缺車成因」才能決定要加站柱、加班次，還是改路線。

**Dashboard 想解的問題**：把「缺車現象」與「缺車背後的供需機制」拆成兩層看，
讓使用者**先辨識誰最痛、再看系統是靠什麼撐住的**，而不是只看一張排行榜就下結論。

**敘事順序（兩個 block）**：

1. **長時段缺車站排行** — *先看「現象」：哪些站長時間處於沒車狀態？*
2. **站點淨流出量排行（含補車依賴度）** — *再看「機制」：這些淨流出最大的站，是靠市民自然還車維持，還是靠調度卡車硬補？*

**核心 insight（用實際資料驗證過）**：

雙北 imbalance `absolute` top-15 中，**15 站全部是高補車依賴（dispatch_dependency ≥ 0.70）**；
單看 Taipei 也是 14/15 高依賴。這代表：

> **「淨流出量最大的站，幾乎全靠調度卡車一次次大筆補車才不至於崩潰。」**

也就是說，整個系統在這些站是**結構性依賴調度**——一旦補車班次中斷，這些站會立刻變成 Block 1 排行頂部那種「整天沒車」的狀態。這不是個別站的問題，而是系統設計層面的需求/補給失衡。

---

## 二、Block 1：YouBike 長時段缺車站排行

### 2.1 要回答的問題

> **「在觀測時段內，哪些站累積最久處於『沒車可借』的狀態？」**

呈現的是「現象」——只回答誰痛、痛多久，不解釋原因。

### 2.2 資料來源

- **來源表**：`hackathon` DB 的 `youbike_snapshots`（與 manager Postgres 共用 instance）
- **時間範圍**：2026/05/01 全日 00:00–23:45 之 15 分鐘間隔快照（24 小時，每站約 96 個 slot）
- **覆蓋城市**：臺北市 1,737 站 + 新北市 1,524 站，合計 3,261 站
- **筆數**：314,793 列快照（雙北合計，含 `scripts/fill-missing-youbike-slots.sql` 補齊缺漏 slot）
- **前端切換**：dashboard tab 控制 `datasetKey` ∈ `{Taipei, All}`

### 2.3 計算邏輯

定義（與 `aggregate.go` 中常數一致）：

| 名稱 | 值 | 意義 |
|---|---|---|
| `emptyThreshold` | `1.0` | 平均可借車輛 < 1 視為「該小時沒車」 |
| `lowRatioThreshold` | `0.2` | 平均可借車輛 / 站柱數 < 20% 視為「車量偏低」 |
| `topNPersistence` | `25` | 後端先取前 25 名 |
| 前端 slice | `20` | 前端再切前 20 名顯示 |

步驟：

1. **小時級聚合**（`aggregateByStation`）
   每個 (station_uid, hour) bucket 內：
   - `avg_available_bikes` = 該小時所有快照的可借車輛平均
   - `total_docks` = 該小時觀測到的最大站柱數（避開站柱動態變動的雜訊）
   - `is_empty` = `avg_available_bikes < 1.0`
   - `is_low` = `avg_available_bikes / total_docks < 0.20`

2. **站點級彙總**（`buildBarPersistence`）
   每個 station_uid：
   - `empty_hours` = 該站滿足 `is_empty` 的小時數
   - `low_hours` = 該站滿足 `is_low` 的小時數
   - `hours_observed` = 該站有觀測資料的不同小時數
   - `empty_hour_ratio` = `empty_hours / hours_observed`
   - `avg_fill_ratio` = 該站每小時 fill_ratio 的平均

3. **排序**（多鍵）
   `empty_hour_ratio DESC` → `low_hour_ratio DESC` → `total_docks DESC`
   為什麼 `empty_hour_ratio` 而非 `empty_hours`：避免觀測時長不齊的站被低估。

4. **取前 20 站**呈現於 BarChart。

### 2.4 視覺呈現

- 圖表類型：`BarChart`（橫向長條）
- X 軸：站點名稱（`stripPrefix` 去掉 `YouBike2.0_` 前綴）
- Y 軸：`empty_hours`（缺車時數）
- 副標：`「觀測 {hours_observed} 小時內」`，提醒讀者分母

### 2.5 怎麼讀

- **頂部**：累計缺車時數最高的站，實測以站柱數較少（15–35 柱）的觀光終點與大學周邊為主，例如臺科大側門、富基漁港、烏來公車總站、石碇、坪林旅遊服務中心；因為車量上限低、達 `is_empty` 門檻所需流出量也低。
- **中段**：缺車時數約 4–6 小時的站，多為都會型小站。
- **看不到的東西**：完全沒有「為什麼」——一個觀光終點站和一個通勤盲區站在這張圖上長得一樣痛，要看 Block 2 才分得開。

---

## 三、Block 2：YouBike 站點淨流出量排行（含補車依賴度）

### 3.1 要回答的問題

> **「為什麼這些站總是沒車？是借的人太多、還是還的人/補車太少？而還回來的車，有多少是市民自然還、多少是調度卡車補？」**

呈現的是「成因」——把缺車拆成「結構性需求」與「調度依賴」兩個面向。

### 3.2 資料來源

同 Block 1，使用同一張 `youbike_snapshots` 表，但**不做小時聚合**——直接用相鄰兩筆 15 分鐘快照的 `available_bikes` 差值來推估借出 / 還回。每站 24 小時內約有 96 筆快照、約 95 個 delta。

### 3.3 計算邏輯

定義：

| 名稱 | 值 | 意義 |
|---|---|---|
| `burstThreshold` | `5` | 兩筆快照之間 `available_bikes` 增加 ≥ 5 視為「調度補車」（人為大筆還車的機率極低） |
| `topNImbalance` | `15` | 後端取前 15 名 |
| `per_dock` 視角過濾門檻 | `total_docks >= 10` | 排除測試站、停用中站 |

步驟（`computeImbalance`）：

1. **逐站排序快照**：依 `snapshot_at` 由舊到新。

2. **逐筆計算 delta**
   `delta = available_bikes[i] - available_bikes[i-1]`

   依 delta 落入三類：
   ```
   delta < 0       → est_borrow += -delta            （估計借出量）
   delta ≥ 5       → est_return += delta              （估計還回）
                     est_return_burst += delta        （其中歸類為「調度補車」）
   0 < delta < 5   → est_return += delta              （估計還回）
                     est_return_steady += delta       （其中歸類為「市民自然還車」）
   ```

3. **逐站彙總**
   - `imbalance` = `est_return - est_borrow`
     - **負值** = 借出 > 還回 = 結構性流出（缺車的根因）
   - `imbalance_per_dock` = `imbalance / max(total_docks, 1)`
   - `dispatch_dependency` = `est_return_burst / max(est_return, 1)`
     - 比例越高，代表這站的車量主要靠調度卡車補進來。

4. **產出兩個視角**
   - `absolute`：依 `imbalance` 升冪（最負在前）取前 15 → 預設前端顯示
   - `per_dock`：先過濾 `total_docks ≥ 10`，再依 `imbalance_per_dock` 升冪取前 15（避免大站永遠霸榜）

5. **前端轉換**（`youbikeShortageBlocks.js`）
   - 顯示值 `y = -imbalance`（把負的「淨流入」翻成正數的「淨流出量」更直觀）
   - 圖表副標統計三類補車依賴的站數分布
   - `dispatch_dependency` 分桶：
     ```
     ≥ 0.70 → 高補車依賴
     ≥ 0.40 → 中補車依賴
     <  0.40 → 低補車依賴
     ```

### 3.4 視覺呈現

- 圖表類型：`BarChart`（橫向長條，與 Block 1 視覺一致）
- X 軸：站點名稱（前 15 名）
- Y 軸：估計淨流出量（單位：輛）
- 副標：`「補車依賴度分布：高補車依賴 X 站、中補車依賴 Y 站、低補車依賴 Z 站」`

### 3.5 怎麼讀（補車依賴度分群）

> **重要：實際資料驗證**（2026/05/01）
> `absolute` top-15 在三個視角下的 dependency 分布：
> - 雙北 (`All`)：高 15 / 中 0 / 低 0
> - Taipei：高 14 / 中 1 / 低 0
> - NewTaipei：高 15 / 中 0 / 低 0
>
> **這是設計上的必然**——`absolute` view 是依「淨流出量最大」排序，本身就會把對調度依賴最重的站推到前面。dashboard 預設顯示這個視角，所以實務上使用者看到的幾乎都是高依賴站。

理論分群（即使在這個 dashboard 上難以同時對照三類，仍是有用的概念框架）：

- **高補車依賴（≥0.7）** ← 預設視角絕大多數落在這
  車量幾乎全靠調度卡車一次次大筆補進來。實際資料看起來像：板橋四維公園、捷運北投站、捷運國父紀念館站、關渡碼頭、國家音樂廳。
  → 行動建議：加站柱、提高補車頻率；光靠流量自然平衡撐不住。

- **中補車依賴（0.4–0.7）**
  自然還車與調度補車各半。Taipei `absolute` top-15 只看到 1 站（南京遼寧街口）。若想看更多此類站，需切到 `per_dock` 視角（前端目前未提供切換）。
  → 行動建議：與時段反向的下游站做配對調度，比單方面加班次更划算。

- **低補車依賴（<0.4）**
  車量主要靠市民自然還車維持。**在 absolute top-15 內幾乎不會出現**（因為淨流出量排行天然偏向高依賴）。要找這類站需要交叉比對：上 Block 1 排行但 `dispatch_dependency` 低 → 是被忽略的調度盲區。
  → 行動建議：把這站納入既有路線，邊際成本最低。

---

## 四、兩塊圖怎麼串起來講

**敘事腳本（建議 60–90 秒，依實際資料調整過）**：

1. *(指 Block 1)* 「先看現象——這 20 站在 2026/05/01 觀測 24 小時內最多累計沒車 13 小時、最少 4 小時，前 12 名都超過 6 小時，是 YouBike 系統最痛的點。其中以站柱數較小（15–35 柱）的觀光終點與大學周邊為主，例如臺科大側門、富基漁港、烏來公車總站。」
2. *(停頓，引出第二張)* 「但 Block 1 沒回答一個關鍵問題：這些站的車是怎麼維持的？」
3. *(切到 Block 2)* 「淨流出量最大的前 15 站站柱數多在 50–100 之間（最小 43 最大 99）、imbalance 介於 -36 到 -72 之間。」
4. *(指副標補車依賴度分布)* 「副標寫著『高補車依賴 15 站』——意思是這些站的還車量幾乎全來自單筆 ≥ 5 輛的大筆變化，幾乎可以肯定是調度卡車補的。」
5. *(放大講)* 「換句話說：YouBike 系統在這些大站是靠**調度硬補**才不崩潰。如果哪一天卡車班次中斷，這些站會立刻沉到 Block 1 那種整天沒車的狀態。這不是個別站的問題，是系統層面的供需失衡。」
6. *(收尾)* 「『缺車成因分析』要傳達的不是『某幾站要修一下』，而是『系統有多大比例是靠調度撐住的』。看清楚這層機制，才談得上要加站柱、加班次，還是調整路網設計。」

**注意**：上述腳本以實際資料為基底，不再做「三物種對照」的論述（在 absolute top-15 內幾乎沒有中／低依賴可對照）。

**為什麼選這兩張、不選其他**：

| 候選組合 | 評估 |
|---|---|
| 2 + 3（本案） | 現象 → 成因，BarChart 對 BarChart 視覺一致，故事完整 ✅ |
| 1 + 2 | 兩張都在描述「現象」（時段佔比 vs 站點累計），缺成因解釋 |
| 1 + 4 | 兩張都是時段視角（全市 vs 單站），主題重疊 |
| 2 + 4 | 一維 bar 對二維 heatmap，敘事節奏不一致 |

---

## 五、已知限制與資料邊界

1. **單日快照**：目前只有 2026/05/01 一天的資料。
   - 平假日差異、季節性、跨日趨勢都不能談。
   - `dispatch_dependency` 在跨日累積後會更穩定；單日資料容易被一兩次大筆調度拉偏。

2. **跨日邊界缺失**：資料只覆蓋 2026/05/01 同一個自然日。
   - 每站只有 95 個 delta（96 筆快照），最後一筆 23:45 與隔日 00:00 之間的變化看不到。
   - 凌晨深夜的調度補車如果跨過 23:45–次日 00:00 邊界，會被切成兩段（前段算入今日尾、後段缺失），可能讓部分站的 `est_return_burst` 被低估、`dispatch_dependency` 偏低。

3. **`burstThreshold = 5` 是經驗門檻**：
   - 當市民連續還回 ≥ 5 輛車的機率極低，但不是 0。
   - 大型停車場附近的站、活動結束時段，可能有市民群體還車被誤判為調度。

4. **`is_empty` 用平均**：
   - 一個小時內只要平均 < 1 輛就算缺車；若該小時有 30 分有車、30 分沒車，平均 ≈ 0.5 仍會被計入。
   - 與線上「YouBike 見車率」（採用任一時刻 ≥ 1 即算有車）的口徑不同，**不可直接比對數字**。

5. **觀光站偏置**：
   - Block 1 排行頂部會被站柱數小的觀光終點佔據，這是設計上的特性（小站達門檻容易），不是 bug。
   - 若要與大型站公平比較，可改看後端 `bar_persistence` 的 `low_hour_ratio` 而非 `empty_hours`。

6. **`imbalance` 不等於真實 OD**：
   - 我們只看單站時序差分，並沒有追蹤車輛在站之間的流向。
   - 真實 OD 矩陣需要參考線上「YouBike2.0 週間群像」「週末群像」資料，**本 dashboard 不取代它**。

7. **`absolute` view 的結構性偏置**：
   - 依「淨流出量最大」排序時，前 15 名幾乎一定落在「高補車依賴」（實測 All 15/15、Taipei 14/15）。
   - 想看到中／低依賴的站，需切到 `per_dock` view（imbalance/docks，且 docks ≥ 10 過濾）——後端已產出但**前端目前沒提供切換 UI**。
   - 影響 user story：本文件的敘事不依賴「三物種對照」這個橋段，避免在簡報時找不到對照案例。

---

## 六、資料管線總覽

```
hackathon-pipeline/data/youbike_{Taipei,NewTaipei}/*.csv
              │
              ▼  scripts/load-ubike-data.sh（rsync + COPY）
              │
hackathon DB ─ youbike_snapshots
              │
              ▼  GET /api/v1/commute/youbike/persistence?city=...
              │   GET /api/v1/commute/youbike/imbalance?city=...
              │  └─ youbike_aggregate.LoadFromDB → BuildPayload
              │     （60 秒 in-process cache，三個 endpoint 共享）
              │
Frontend ─ contentStore.setCurrentDashboardAllChartData
              │   └─ 看到 chart_config.api_endpoint 就改打對應 URL，
              │      response 直接灌入 component.chart_data
              │
Dashboard tab ── youbike-analysis-{taipei,metrotaipei}
                 6 個 component 中第 3、4 即為本文件主敘事的兩個 block
```
