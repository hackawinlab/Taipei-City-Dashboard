"""
populate_db.py — 分析公車 ETA 誤差，結果寫入 PostgreSQL + 匯出 GeoJSON
每 5 分鐘跑一次（by cron）

環境變數：
  DASHBOARD_DB_HOST     PostgreSQL host（預設 localhost）
  DASHBOARD_DB_PORT     PostgreSQL port（預設 5433）
  DASHBOARD_DB_NAME     DB 名稱（預設 dashboard）
  DASHBOARD_DB_USER     DB 使用者（預設 postgres）
  DASHBOARD_DB_PASS     DB 密碼（預設 postgres）
  DASHBOARD_FE_PUBLIC   FE public/ 目錄絕對路徑，用於寫出 GeoJSON
                        （預設：本 script 往上 3 層的 Taipei-City-Dashboard-FE/public/）
  BUS_DATA_DIR          ETA snapshot CSV 目錄（預設：./data）
"""
import sys, os, json, psycopg2
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map import load_route, build_segments_geojson, build_delta_segments_geojson, ROUTES, DATA_DIR as _DEFAULT_DATA_DIR
import analyze as az

DATE  = datetime.now().strftime('%Y%m%d')
HOURS = 3.0

DB_HOST = os.environ.get('DASHBOARD_DB_HOST', 'localhost')
DB_PORT = int(os.environ.get('DASHBOARD_DB_PORT', '5433'))
DB_NAME = os.environ.get('DASHBOARD_DB_NAME', 'dashboard')
DB_USER = os.environ.get('DASHBOARD_DB_USER', 'postgres')
DB_PASS = os.environ.get('DASHBOARD_DB_PASS', 'postgres')

# GeoJSON 輸出目錄：預設往上找 FE public/mapData/
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_FE_PUBLIC = os.path.normpath(
    os.path.join(_SCRIPT_DIR, '..', '..', 'Taipei-City-Dashboard-FE', 'public')
)
GEO_DIR = os.path.join(
    os.environ.get('DASHBOARD_FE_PUBLIC', _DEFAULT_FE_PUBLIC),
    'mapData'
)
os.makedirs(GEO_DIR, exist_ok=True)

DATA_DIR = os.environ.get('BUS_DATA_DIR', _DEFAULT_DATA_DIR)


def _is_valid_seg(feat, max_km=2.0):
    import math
    coords = feat["geometry"]["coordinates"]
    if len(coords) != 2:
        return True  # 有 shape 幾何的不過濾
    c0, c1 = coords[0], coords[1]
    dlat = (c0[1]-c1[1]) * 111
    dlon = (c0[0]-c1[0]) * 111 * math.cos(math.radians((c0[1]+c1[1])/2))
    return math.sqrt(dlat**2 + dlon**2) <= max_km


def run():
    all_feats_abs   = []
    all_feats_delta = []

    for city_key in ['taipei', 'newtaipei']:
        print(f'[{city_key}] 載入資料...')
        raw_stops, stop_map, stop_errors, groups, all_results, shape_map, stop_ewma = \
            load_route(city_key, DATE, DATA_DIR, hours=HOURS)
        if raw_stops is None:
            print(f'  [{city_key}] 無資料，跳過')
            continue

        seg_deltas, seg_meta = az.compute_segment_deltas(all_results)
        print(f'  arrival events: {len(all_results)}, segments: {len(seg_deltas)}')

        gj_abs   = build_segments_geojson(stop_map, stop_errors, raw_stops, shape_map)
        gj_delta = build_delta_segments_geojson(seg_deltas, stop_errors, raw_stops, shape_map)

        city_label = '台北市' if city_key == 'taipei' else '新北市'
        for f in gj_abs['features']:
            f['properties']['city'] = city_label
        for f in gj_delta['features']:
            f['properties']['city'] = city_label

        all_feats_abs.extend(f for f in gj_abs["features"] if _is_valid_seg(f))
        all_feats_delta.extend(f for f in gj_delta["features"] if _is_valid_seg(f))

    if not all_feats_abs:
        print('無任何資料，結束')
        return

    # ── 寫入 GeoJSON 靜態檔 ───────────────────────────────────────
    abs_path   = os.path.join(GEO_DIR, 'bus_congestion_abs.geojson')
    delta_path = os.path.join(GEO_DIR, 'bus_congestion_delta.geojson')

    with open(abs_path, 'w') as f:
        json.dump({'type': 'FeatureCollection', 'features': all_feats_abs}, f, ensure_ascii=False)
    with open(delta_path, 'w') as f:
        json.dump({'type': 'FeatureCollection', 'features': all_feats_delta}, f, ensure_ascii=False)
    print(f'GeoJSON → {GEO_DIR}  (abs:{len(all_feats_abs)}, delta:{len(all_feats_delta)})')

    # ── 寫入 PostgreSQL ───────────────────────────────────────────
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                            user=DB_USER, password=DB_PASS)
    cur  = conn.cursor()
    cur.execute('TRUNCATE bus_congestion_segments')

    for f in all_feats_delta:
        p = f['properties']
        cur.execute('''
            INSERT INTO bus_congestion_segments
              (seg_id, from_name, to_name, direction, city,
               seg_err, color, label, has_delta, n_samples, geojson, updated_at)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW())
        ''', (
            p.get('seg_id',''),
            p.get('from_name',''), p.get('to_name',''),
            p.get('direction',''), p.get('city',''),
            p.get('seg_err'), p.get('color','#bbbbbb'),
            p.get('label','無資料'),
            bool(p.get('has_delta', False)),
            p.get('n_samples', 0),
            json.dumps(f, ensure_ascii=False)
        ))

    conn.commit()
    conn.close()
    print(f'DB 寫入 {len(all_feats_delta)} 筆路段  updated_at={datetime.now():%H:%M:%S}')


if __name__ == '__main__':
    run()
