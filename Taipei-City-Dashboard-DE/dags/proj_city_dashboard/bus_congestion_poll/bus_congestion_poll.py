from airflow import DAG
from operators.common_pipeline import CommonDag


def _bus_congestion_poll(**kwargs):
    """
    一次性抓取台北市 + 新北市全路線 ETA snapshot，append 到每日 CSV。
    由 Airflow 每 2 分鐘觸發一次（取代 poller.py 的 while 迴圈）。

    CSV 路徑：{data_path}/bus_congestion/eta_snapshots_{city}_{YYYYMMDD}.csv
    """
    import os
    import csv
    import gzip
    import json
    import urllib.request
    from datetime import datetime

    from utils.auth_tdx import TDXAuth

    data_path = kwargs.get("data_path")
    DATA_DIR = os.path.join(data_path, "bus_congestion")
    os.makedirs(DATA_DIR, exist_ok=True)

    TAIPEI_ETA_URL = "https://tcgbusfs.blob.core.windows.net/blobbus/GetEstimateTime.gz"
    NEWTAIPEI_ETA_URL = (
        "https://tdx.transportdata.tw/api/basic/v2/Bus"
        "/EstimatedTimeOfArrival/City/NewTaipei?$format=JSON"
    )
    CSV_HEADER = ["timestamp", "source_time", "StopID", "RouteUID", "GoBack", "EstimateTime_s"]

    now = datetime.now()
    ts = now.strftime("%Y-%m-%d %H:%M:%S")
    date_str = now.strftime("%Y%m%d")

    def _init_csv(path):
        if not os.path.exists(path):
            with open(path, "w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerow(CSV_HEADER)

    def _append_rows(path, rows):
        with open(path, "a", newline="", encoding="utf-8") as f:
            csv.writer(f).writerows(rows)

    # ── 台北市（blob，無需 auth）───────────────────────────────────
    tpe_csv = os.path.join(DATA_DIR, f"eta_snapshots_taipei_{date_str}.csv")
    _init_csv(tpe_csv)
    try:
        req = urllib.request.Request(
            TAIPEI_ETA_URL, headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(gzip.decompress(r.read()))
        src_ts = data.get("EssentialInfo", {}).get("UpdateTime", "")
        rows = []
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
            rows.append([ts, src_ts, sid, route, gob, eta_s])
        _append_rows(tpe_csv, rows)
        print(f"[台北市] {len(rows):,} 站 寫入 {tpe_csv}")
    except Exception as e:
        print(f"[台北市] ⚠️ fetch 失敗：{e}")

    # ── 新北市（TDX API）──────────────────────────────────────────
    nwt_csv = os.path.join(DATA_DIR, f"eta_snapshots_newtaipei_{date_str}.csv")
    _init_csv(nwt_csv)
    try:
        auth = TDXAuth()
        token = auth.get_token()
        req = urllib.request.Request(
            NEWTAIPEI_ETA_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": "Mozilla/5.0",
                "Accept-Encoding": "gzip",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
        try:
            raw = gzip.decompress(raw)
        except Exception:
            pass
        data = json.loads(raw)
        rows = []
        for e in data:
            eta_s = e.get("EstimateTime", -1)
            if not isinstance(eta_s, int) or eta_s < 0:
                continue
            sid    = str(e.get("StopID", ""))
            route  = str(e.get("RouteUID", "") or e.get("RouteName", {}).get("Zh_tw", ""))
            gob    = str(e.get("Direction", "0"))
            src_ts = e.get("SrcUpdateTime", "")
            if not sid:
                continue
            rows.append([ts, src_ts, sid, route, gob, eta_s])
        _append_rows(nwt_csv, rows)
        print(f"[新北市] {len(rows):,} 站 寫入 {nwt_csv}")
    except Exception as e:
        print(f"[新北市] ⚠️ fetch 失敗：{e}")


dag = CommonDag(
    proj_folder="proj_city_dashboard", dag_folder="bus_congestion_poll"
)
dag.create_dag(etl_func=_bus_congestion_poll)
