"""
公車 ETA poller（全城版）
2 calls / 90s：
  台北市 — data.taipei blob（無 auth，無 rate limit）
  新北市 — TDX API（OAuth2，1 call /poll，28,800/月 << 100k 上限）

輸出：
  data/eta_snapshots_taipei_YYYYMMDD.csv     台北市全路線
  data/eta_snapshots_newtaipei_YYYYMMDD.csv  新北市全路線

CSV 欄位：timestamp, source_time, StopID, RouteUID, GoBack, EstimateTime_s

環境變數：
  TDX_CLIENT_ID      TDX API Client ID（申請：https://tdx.transportdata.tw）
  TDX_CLIENT_SECRET  TDX API Client Secret
  BUS_DATA_DIR       資料存放目錄（預設：./data）
"""

import json, time, os, gzip, csv, urllib.request, urllib.parse
from datetime import datetime

# ── 設定 ──────────────────────────────────────────────────────────────────
POLL_INTERVAL_S = 90

TDX_CLIENT_ID     = os.environ.get("TDX_CLIENT_ID", "")
TDX_CLIENT_SECRET = os.environ.get("TDX_CLIENT_SECRET", "")
TDX_TOKEN_URL     = ("https://tdx.transportdata.tw/auth/realms/TDXConnect"
                     "/protocol/openid-connect/token")

TAIPEI_ETA_URL    = "https://tcgbusfs.blob.core.windows.net/blobbus/GetEstimateTime.gz"
NEWTAIPEI_ETA_URL = ("https://tdx.transportdata.tw/api/basic/v2/Bus"
                     "/EstimatedTimeOfArrival/City/NewTaipei?$format=JSON")

DATA_DIR = os.environ.get("BUS_DATA_DIR",
                          os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
CSV_HEADER = ["timestamp", "source_time", "StopID", "RouteUID", "GoBack", "EstimateTime_s"]

# ── TDX OAuth ──────────────────────────────────────────────────────────────
_tdx_token     = None
_tdx_token_exp = 0

def get_tdx_token():
    global _tdx_token, _tdx_token_exp
    if not TDX_CLIENT_ID or not TDX_CLIENT_SECRET:
        raise RuntimeError("TDX_CLIENT_ID / TDX_CLIENT_SECRET 未設定，無法取得新北市資料")
    now = time.time()
    if _tdx_token and now < _tdx_token_exp - 60:
        return _tdx_token
    body = urllib.parse.urlencode({
        "grant_type":    "client_credentials",
        "client_id":     TDX_CLIENT_ID,
        "client_secret": TDX_CLIENT_SECRET,
    }).encode()
    req = urllib.request.Request(TDX_TOKEN_URL, data=body, headers={
        "Content-Type": "application/x-www-form-urlencoded"
    })
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    _tdx_token     = data["access_token"]
    _tdx_token_exp = now + data.get("expires_in", 1800)
    return _tdx_token


# ── Fetch ──────────────────────────────────────────────────────────────────
def fetch_taipei_all():
    req = urllib.request.Request(TAIPEI_ETA_URL,
                                 headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(gzip.decompress(r.read()))

    src_ts = data.get("EssentialInfo", {}).get("UpdateTime", "")
    rows, routes = [], set()
    for e in data.get("BusInfo", []):
        try:
            eta_s = int(e.get("EstimateTime", -1))
        except (ValueError, TypeError):
            continue
        if eta_s < 0:
            continue
        sid   = str(e.get("StopID", ""))
        route = str(e.get("RouteID", ""))
        gob   = str(e.get("GoBack", "0"))
        if not sid:
            continue
        rows.append((sid, route, gob, eta_s))
        routes.add(route)
    return rows, src_ts, len(routes)


def fetch_newtaipei_all():
    token = get_tdx_token()
    req = urllib.request.Request(NEWTAIPEI_ETA_URL, headers={
        "Authorization":  f"Bearer {token}",
        "User-Agent":     "Mozilla/5.0",
        "Accept-Encoding": "gzip",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
    try:
        raw = gzip.decompress(raw)
    except Exception:
        pass
    data = json.loads(raw)

    rows, routes = [], set()
    for e in data:
        eta_s = e.get("EstimateTime", -1)
        if not isinstance(eta_s, int) or eta_s < 0:
            continue
        sid    = str(e.get("StopID", ""))
        route  = str(e.get("RouteUID", "") or
                     e.get("RouteName", {}).get("Zh_tw", ""))
        gob    = str(e.get("Direction", "0"))
        src_ts = e.get("SrcUpdateTime", "")
        if not sid:
            continue
        rows.append((sid, route, gob, eta_s, src_ts))
        routes.add(route)
    return rows, len(routes)


# ── CSV helpers ────────────────────────────────────────────────────────────
def init_csv(path):
    if not os.path.exists(path):
        with open(path, "w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(CSV_HEADER)

def append_rows(path, rows):
    with open(path, "a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


# ── 主迴圈 ────────────────────────────────────────────────────────────────
def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    date_str = datetime.now().strftime("%Y%m%d")
    csv_tpe  = os.path.join(DATA_DIR, f"eta_snapshots_taipei_{date_str}.csv")
    csv_nwt  = os.path.join(DATA_DIR, f"eta_snapshots_newtaipei_{date_str}.csv")

    init_csv(csv_tpe)
    init_csv(csv_nwt)

    poll_count = 0
    print(f"🚌 全城 ETA poller 啟動（每 {POLL_INTERVAL_S}s）")
    print(f"   台北市 → {csv_tpe}")
    print(f"   新北市 → {csv_nwt}")
    print(f"   Ctrl+C 停止\n")

    try:
        while True:
            poll_count += 1
            now = datetime.now()
            ts  = now.strftime("%Y-%m-%d %H:%M:%S")

            # ── 台北市（blob）────────────────────────────────────────
            try:
                t0 = time.time()
                tpe_rows, src_ts, n_tpe_routes = fetch_taipei_all()
                csv_rows = [[ts, src_ts, sid, route, gob, eta_s]
                            for sid, route, gob, eta_s in tpe_rows]
                append_rows(csv_tpe, csv_rows)
                print(f"[{ts}] #{poll_count}  "
                      f"台北: {len(csv_rows):>6,} 站 / {n_tpe_routes} 路 "
                      f"({time.time()-t0:.1f}s)", end="")
            except Exception as e:
                print(f"[{ts}] ⚠️ 台北 fetch 失敗：{e}", end="")

            # ── 新北市（TDX）─────────────────────────────────────────
            try:
                t0 = time.time()
                nwt_rows, n_nwt_routes = fetch_newtaipei_all()
                csv_rows = [[ts, src_ts, sid, route, gob, eta_s]
                            for sid, route, gob, eta_s, src_ts in nwt_rows]
                append_rows(csv_nwt, csv_rows)
                print(f"  新北: {len(csv_rows):>6,} 站 / {n_nwt_routes} 路 "
                      f"({time.time()-t0:.1f}s)")
            except Exception as e:
                print(f"  ⚠️ 新北 fetch 失敗：{e}\n")

            time.sleep(POLL_INTERVAL_S)

    except KeyboardInterrupt:
        print(f"\n⏹  停止。共 {poll_count} 次 poll。資料在 {DATA_DIR}/")


if __name__ == "__main__":
    main()
