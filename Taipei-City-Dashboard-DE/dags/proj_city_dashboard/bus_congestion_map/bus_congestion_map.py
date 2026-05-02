from airflow import DAG
from operators.common_pipeline import CommonDag


def _bus_congestion_map(**kwargs):
    """
    每 5 分鐘：讀取最近 3h 的 ETA snapshot CSV → 分析壅塞 → 寫 GeoJSON + PostgreSQL。

    Airflow Variables：
      DASHBOARD_FE_PUBLIC_DIR  FE public/ 目錄絕對路徑（GeoJSON 輸出用）
                               預設：{data_path}/bus_congestion_geojson/

    ready_data_db_uri → dashboard DB（bus_congestion_segments table）
    """
    import os
    import sys
    import json
    import math
    from datetime import datetime
    from urllib.parse import urlparse

    from airflow.models import Variable

    # ── import 核心分析 / 地圖邏輯 ──────────────────────────────────
    # analyze.py / make_map.py 放在 dags/utils/bus_congestion/
    import utils.bus_congestion.analyze as az
    from utils.bus_congestion.make_map import (
        load_route,
        build_segments_geojson,
        build_delta_segments_geojson,
        ROUTES,
    )

    # ── Config ────────────────────────────────────────────────────
    data_path        = kwargs.get("data_path")
    ready_data_db_uri = kwargs.get("ready_data_db_uri")
    DATA_DIR = os.path.join(data_path, "bus_congestion")

    _default_geo_dir = os.path.join(data_path, "bus_congestion_geojson")
    fe_public = Variable.get("DASHBOARD_FE_PUBLIC_DIR", default_var=_default_geo_dir)
    GEO_DIR   = os.path.join(fe_public, "mapData")
    os.makedirs(GEO_DIR, exist_ok=True)

    DATE  = datetime.now().strftime("%Y%m%d")
    HOURS = 3.0

    # ── 分析 ──────────────────────────────────────────────────────
    def _is_valid_seg(feat, max_km=2.0):
        coords = feat["geometry"]["coordinates"]
        if len(coords) != 2:
            return True
        c0, c1 = coords[0], coords[1]
        dlat = (c0[1] - c1[1]) * 111
        dlon = (c0[0] - c1[0]) * 111 * math.cos(math.radians((c0[1] + c1[1]) / 2))
        return math.sqrt(dlat ** 2 + dlon ** 2) <= max_km

    all_feats_abs   = []
    all_feats_delta = []

    for city_key in ["taipei", "newtaipei"]:
        print(f"[{city_key}] 載入資料...")
        result = load_route(city_key, DATE, DATA_DIR, hours=HOURS)
        if result is None or result[0] is None:
            print(f"  [{city_key}] 無資料，跳過")
            continue
        raw_stops, stop_map, stop_errors, groups, all_results, shape_map, stop_ewma = result

        seg_deltas, seg_meta = az.compute_segment_deltas(all_results)
        print(f"  arrival events: {len(all_results)}, segments: {len(seg_deltas)}")

        gj_abs   = build_segments_geojson(stop_map, stop_errors, raw_stops, shape_map)
        gj_delta = build_delta_segments_geojson(seg_deltas, stop_errors, raw_stops, shape_map)

        city_label = "台北市" if city_key == "taipei" else "新北市"
        for f in gj_abs["features"]:
            f["properties"]["city"] = city_label
        for f in gj_delta["features"]:
            f["properties"]["city"] = city_label

        all_feats_abs.extend(f for f in gj_abs["features"] if _is_valid_seg(f))
        all_feats_delta.extend(f for f in gj_delta["features"] if _is_valid_seg(f))

    if not all_feats_abs:
        print("無任何資料，結束")
        return

    # ── 寫入 GeoJSON ──────────────────────────────────────────────
    abs_path   = os.path.join(GEO_DIR, "bus_congestion_abs.geojson")
    delta_path = os.path.join(GEO_DIR, "bus_congestion_delta.geojson")

    with open(abs_path, "w") as f:
        json.dump({"type": "FeatureCollection", "features": all_feats_abs}, f, ensure_ascii=False)
    with open(delta_path, "w") as f:
        json.dump({"type": "FeatureCollection", "features": all_feats_delta}, f, ensure_ascii=False)
    print(f"GeoJSON → {GEO_DIR}  (abs:{len(all_feats_abs)}, delta:{len(all_feats_delta)})")

    # ── 寫入 PostgreSQL ───────────────────────────────────────────
    import psycopg2
    parsed = urlparse(ready_data_db_uri)
    conn = psycopg2.connect(
        host=parsed.hostname,
        port=parsed.port or 5432,
        dbname=parsed.path.lstrip("/"),
        user=parsed.username,
        password=parsed.password,
    )
    cur = conn.cursor()
    cur.execute("TRUNCATE bus_congestion_segments")

    for f in all_feats_delta:
        p = f["properties"]
        cur.execute(
            """
            INSERT INTO bus_congestion_segments
              (seg_id, from_name, to_name, direction, city,
               seg_err, color, label, has_delta, n_samples, geojson, updated_at)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW())
            """,
            (
                p.get("seg_id", ""),
                p.get("from_name", ""),
                p.get("to_name", ""),
                p.get("direction", ""),
                p.get("city", ""),
                p.get("seg_err"),
                p.get("color", "#bbbbbb"),
                p.get("label", "無資料"),
                bool(p.get("has_delta", False)),
                p.get("n_samples", 0),
                json.dumps(f, ensure_ascii=False),
            ),
        )

    conn.commit()
    conn.close()
    print(f"DB 寫入 {len(all_feats_delta)} 筆  updated_at={datetime.now():%H:%M:%S}")


dag = CommonDag(
    proj_folder="proj_city_dashboard", dag_folder="bus_congestion_map"
)
dag.create_dag(etl_func=_bus_congestion_map)
