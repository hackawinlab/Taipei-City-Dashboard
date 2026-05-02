# 食安早期預警系統 PoC

整合社群輿情爬蟲、NLP 分類與群聚偵測，提供食品安全事件的早期預警，並透過 Taipei City Dashboard 視覺化呈現雙北地區食安風險分布。

---

## 專案概述

台灣每年發生數百起食品安全事件，其中許多在官方稽查介入之前，早已在 PTT、Dcard 等社群平台出現相關討論。本系統透過以下流程，縮短「事件發生」到「衛生局掌握」之間的時間差：

1. 每小時從 PTT Food/Gossiping 版與 Dcard 爬取食安相關貼文
2. 使用 NLP 分類器將貼文歸類（食物中毒 / 衛生疑慮 / 異物混入 / 標示不符）
3. 以時空群聚演算法（DBSCAN-like）偵測同一行政區、同一時間窗格內的貼文聚集
4. 群聚超過閾值時觸發早期預警，並更新 Dashboard 組件

---

## 架構說明

```
PTT / Dcard
    │
    ▼
crawler.py          ← 定時爬蟲，取得含食安關鍵字的貼文
    │
    ▼
classifier.py       ← NLP 分類（食物中毒 / 衛生疑慮 / 異物混入 / 標示不符）
    │
    ▼
detector.py         ← 時空群聚偵測，輸出群聚事件與風險評分
    │
    ▼
main.py             ← 主程式入口，整合上述模組，支援 --demo 模式
    │
    ├── PostgreSQL  ← 寫入 food_safety_posts / food_safety_clusters
    │
    └── Dashboard   ← 4 個 Vue 組件讀取 DB 資料後視覺化呈現
              ├── FoodSafetyAlertMap         (地圖點位)
              ├── FoodSafetyRiskLayer        (行政區塗層)
              ├── FoodSafetyTrend            (趨勢折線圖)
              └── FoodSafetyViolationSummary (違規統計長條圖)
```

---

## 4 個 Dashboard 組件

| 組件名稱 | index | 圖表類型 | 說明 |
|---------|-------|---------|------|
| 食安警報地圖 | `food_safety_alert_map` | MapLegend + symbol layer | 於地圖標示各稽查點位，依違規程度以顏色區分（綠/橙/紅） |
| 食安風險行政區塗層 | `food_safety_risk_layer` | MapLegend + **fill layer** | 以 Mapbox fill layer 將行政區依違規率塗色，支援點擊篩選 |
| 食安貼文趨勢 | `food_safety_trend` | TimelineSeparateChart | 近 30 天各類別社群貼文每日數量折線趨勢，標示群聚預警時間點 |
| 違規統計摘要 | `food_safety_violation_summary` | ColumnChart | 各行政區合格/不合格件數堆疊直條圖，支援地圖連動篩選 |

---

## 快速啟動 PoC

### 環境需求

- Python 3.10+
- 依賴套件見 `backend/requirements.txt`

### 安裝

```bash
cd food-safety-poc/backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 執行（Demo 模式，不需要真實爬蟲）

```bash
python main.py --demo
```

Demo 模式會使用內建假資料跑完完整流程（爬取 → 分類 → 群聚偵測），並輸出分析結果摘要至終端機，不需要 DB 連線。

### 連接真實資料庫執行

```bash
# 先匯入 DB migration
psql -U postgres -d dashboard -f ../db/food_safety_components.sql

# 設定環境變數
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=dashboard
export DB_USER=postgres
export DB_PASSWORD=yourpassword

# 執行完整流程
python main.py
```

---

## Mock Data 說明

### `data/mock_inspection_points.geojson`

- 台北市 10 個 + 新北市 10 個假稽查點位
- 每個點位包含：商家名稱、地址、違規數（0–5）、稽查結果、城市、行政區
- 座標均在台北（lat 25.01–25.08, lng 121.49–121.60）與新北（lat 24.95–25.02, lng 121.46–121.67）範圍內

### `data/mock_risk_districts.geojson`

- 台北市 5 個行政區（中山、大安、信義、中正、松山）的簡化矩形多邊形
- 每個 feature 包含：行政區、城市、各風險等級案件數、風險等級、違規率
- Mapbox fill layer 依 `risk_level` 屬性上色：高風險 `#C0392B`、中風險 `#E67E22`、低風險 `#2ECC71`

### `db/food_safety_components.sql`

- 建立 3 個資料表：`food_safety_inspections`、`food_safety_posts`、`food_safety_clusters`
- 插入台北市各行政區共 13 筆假稽查記錄、10 筆假社群貼文偵測記錄、5 筆群聚事件
- 插入 4 個 Dashboard 組件設定（`component_charts`、`component_maps`、`query_charts`、`components`）
- 建立 `food_safety_taipei` Dashboard，將 4 個組件加入

---

## TODO / 未來方向

- [ ] 接入真實 PTT API（目前 PTT 有 rate limit，需排程錯開）
- [ ] 接入 Dcard 公開 API
- [ ] NLP 分類器訓練：以標記過的食安貼文 fine-tune BERT-based 模型，取代目前的關鍵字規則分類
- [ ] 新增新北市稽查資料表與對應組件（`city: newtaipei`）
- [ ] 群聚偵測門檻動態調整（依行政區人口密度正規化）
- [ ] 整合衛生福利部食品安全事件通報系統 API
- [ ] Line Notify / Telegram Bot 預警推播
- [ ] 歷史資料回顧模式（history_config）
