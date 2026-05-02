# Bus Congestion PoC — 公車壅塞偵測

以公車 ETA 預測誤差為代理指標，偵測全城道路壅塞狀況（probe vehicle approach）。

## 架構

```
poller.py       每 90s 抓台北市 + 新北市全路線 ETA snapshot → data/*.csv
populate_db.py  每 5min 由 cron 觸發：分析 CSV → 寫 GeoJSON + PostgreSQL
analyze.py      ETA 誤差分析核心邏輯（被 populate_db.py import）
make_map.py     壅塞地圖生成邏輯（被 populate_db.py import）
```

兩個輸出地圖層（每 5 分鐘更新）：
- **bus_congestion_abs**：累積 ETA 誤差（每站「比系統預測晚幾秒」）
- **bus_congestion_delta**：路段 Δerror（精確定位「這段路本身」的壅塞）

## 快速開始

### 1. 安裝依賴

```bash
pip install -r requirements.txt
```

### 2. 設定環境變數

```bash
cp .env.example .env
# 填入 TDX_CLIENT_ID / TDX_CLIENT_SECRET
# 申請帳號：https://tdx.transportdata.tw
```

### 3. DB Migration

在 **dashboardmanager** DB（port 5432）與 **dashboard** DB（port 5433）執行：

```bash
# dashboard DB（建 bus_congestion_segments table）
psql -h localhost -p 5433 -U postgres -d dashboard \
  -f ../../db-sample-data/bus-congestion.sql

# dashboardmanager DB（新增 component 設定）
psql -h localhost -p 5432 -U postgres -d dashboardmanager \
  -f ../../db-sample-data/bus-congestion-manager.sql
```

### 4. 啟動 Poller

```bash
# 載入 env
source .env  # 或 export TDX_CLIENT_ID=... TDX_CLIENT_SECRET=...

# 背景執行
nohup python3 poller.py > logs/poller.log 2>&1 &
```

### 5. 設定 Cron（每 5 分鐘更新地圖）

```bash
# 編輯 crontab
crontab -e

# 加入以下行（調整路徑）：
# */5 * * * * cd /path/to/bus-congestion && source .env && python3 populate_db.py >> logs/populate.log 2>&1
```

## 演算法說明

| 改進 | 說明 |
|------|------|
| Median predicted arrival | 取 ETA 窗口內所有預測到站時間的 median，比第一個樣本穩定 |
| RouteUID grouping | 以路線 UID 區分不同班車，避免跨路線誤判 |
| EWMA time decay | α=0.35 衰減舊資料，反映最新壅塞狀況 |
| Seq-aware shape matching | window=0.20 的序列感知形狀匹配，正確對應站點到路線幾何 |

## 色階說明

| 顏色 | 標籤 | ETA 誤差 |
|------|------|---------|
| 🟢 #2ecc71 | 暢通（≤0s） | 準點或提早 |
| 🟡 #f1c40f | 輕微（+1~30s） | 輕微延誤 |
| 🟠 #e67e22 | 中度（+31~60s） | 中度壅塞 |
| 🔴 #e74c3c | 嚴重（+61~120s） | 嚴重壅塞 |
| 🟥 #8e1010 | 極嚴重（>120s） | 極度壅塞 |
| ⬜ #bbbbbb | 無資料 | 樣本不足 |

## 資料來源

- 台北市：[data.taipei Blob API](https://tcgbusfs.blob.core.windows.net/blobbus/GetEstimateTime.gz)（無需 auth）
- 新北市：[TDX 運輸資料流通服務](https://tdx.transportdata.tw)（需申請帳號，免費方案 100k/月 足夠）
