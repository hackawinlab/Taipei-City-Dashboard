"""
產生兩張 Google Maps 風格壅塞地圖：
  map.html       — 絕對誤差（每站「比系統預測晚幾秒」）
  map-delta.html — 路段增量（Δerror：這段路本身多花幾秒）
用法：python3 make_map.py [--date YYYYMMDD]
"""

import json, argparse, os, sys
from datetime import datetime
from collections import defaultdict

# ── 路線幾何：WKT 解析 + 最近點子路徑 ──────────────────────────────────────────

def _parse_wkt_linestring(wkt):
    """'LINESTRING (lon lat, lon lat, ...)' → [[lon, lat], ...]"""
    try:
        i = wkt.index('(') + 1
        j = wkt.rindex(')')
        coords = []
        for pair in wkt[i:j].split(','):
            parts = pair.strip().split()
            if len(parts) >= 2:
                coords.append([float(parts[0]), float(parts[1])])
        return coords
    except Exception:
        return []


def load_shapes(shapes_path, city_key):
    """
    讀取 city_shapes_{city}_{date}.json，建立 shape lookup dict。
    返回 {(route_key, direction_str): [[lon, lat], ...]}
      city_key == "taipei"    → route_key 用 RouteID（數字字串，如 "10132"）
      city_key == "newtaipei" → route_key 用 RouteUID（如 "NWT10116"）
    """
    shape_map = {}
    if not shapes_path or not os.path.exists(shapes_path):
        return shape_map
    with open(shapes_path) as f:
        shapes = json.load(f)
    for s in shapes:
        geo = s.get("Geometry", "")
        if not geo or not geo.upper().startswith("LINESTRING"):
            continue
        coords = _parse_wkt_linestring(geo)
        if len(coords) < 2:
            continue
        direction = str(s.get("Direction", "0"))
        if city_key == "taipei":
            rkey = str(s.get("RouteID", ""))
        else:
            rkey = str(s.get("RouteUID", ""))
        if rkey:
            shape_map[(rkey, direction)] = coords
    return shape_map


def _nearest_idx(coords, lon, lat):
    """在 coords 中找距離 (lon, lat) 最近的點的 index"""
    best_i, best_d2 = 0, float('inf')
    for i, c in enumerate(coords):
        d2 = (c[0] - lon) ** 2 + (c[1] - lat) ** 2
        if d2 < best_d2:
            best_d2, best_i = d2, i
    return best_i


def _nearest_idx_seq(coords, lon, lat, seq_frac, window=0.20):
    """
    Sequence-aware 版本：只在 seq_frac ± window 的範圍內搜尋最近點。
    seq_frac: 這站在整條路線的估計位置（0.0 = 起點，1.0 = 終點）
    window:   搜尋窗口寬度（預設 ±20%）
    """
    n = len(coords)
    lo = max(0, int((seq_frac - window) * n))
    hi = min(n - 1, int((seq_frac + window) * n))
    best_i, best_d2 = lo, float('inf')
    for k in range(lo, hi + 1):
        d2 = (coords[k][0] - lon) ** 2 + (coords[k][1] - lat) ** 2
        if d2 < best_d2:
            best_d2, best_i = d2, k
    return best_i


def get_subpath(shape_coords, lon_a, lat_a, lon_b, lat_b):
    """
    從 shape_coords 中擷取 A→B 之間的子路徑。
    找各自最近點，取中間那段；若退化或 span 過大則 fallback 到直線。

    span 防護：若 sub-segment > min(100, 25% of route) 個點，
    代表 stop-shape 對不上（sub-route vs 全程 mismatch），退回直線。
    """
    if not shape_coords or len(shape_coords) < 2:
        return [[lon_a, lat_a], [lon_b, lat_b]]
    i_a = _nearest_idx(shape_coords, lon_a, lat_a)
    i_b = _nearest_idx(shape_coords, lon_b, lat_b)
    lo, hi = min(i_a, i_b), max(i_a, i_b)
    max_span = min(100, int(len(shape_coords) * 0.25) + 1)
    if hi - lo > max_span:
        return [[lon_a, lat_a], [lon_b, lat_b]]   # fallback 直線
    sub = shape_coords[lo: hi + 1]
    if len(sub) < 2:
        return [[lon_a, lat_a], [lon_b, lat_b]]
    return sub


def get_subpath_seq(shape_coords, lon_a, lat_a, lon_b, lat_b,
                    seq_frac_a=0.0, seq_frac_b=1.0):
    """
    Sequence-aware 版本：用 seq_frac 縮小搜尋範圍，
    避免 sub-route vs 全程 mismatch（不需要 span 防護）。
    """
    if not shape_coords or len(shape_coords) < 2:
        return [[lon_a, lat_a], [lon_b, lat_b]]
    i_a = _nearest_idx_seq(shape_coords, lon_a, lat_a, seq_frac_a)
    i_b = _nearest_idx_seq(shape_coords, lon_b, lat_b, seq_frac_b)
    lo, hi = min(i_a, i_b), max(i_a, i_b)
    sub = shape_coords[lo: hi + 1]
    if len(sub) < 2:
        return [[lon_a, lat_a], [lon_b, lat_b]]
    return sub


# ── EWMA 輔助 ────────────────────────────────────────────────────────────────

EWMA_ALPHA = 0.35   # 衰減係數：0.35 ≈ 半衰期 2 個 event


def compute_ewma(all_results):
    """
    對每個 (sid, gob) 計算 EWMA-weighted 誤差（越近期的 arrival event 權重越高）。
    回傳 {(sid, gob): ewma_error_s}
    """
    from collections import defaultdict
    stop_timed = defaultdict(list)
    for r in all_results:
        stop_timed[(r["sid"], r["gob"])].append((r["actual_ts"], r["error_s"]))

    stop_ewma = {}
    for (sid, gob), timed in stop_timed.items():
        timed.sort(key=lambda x: x[0])   # 按到站時間排序
        val = None
        for _, e in timed:
            val = e if val is None else EWMA_ALPHA * e + (1 - EWMA_ALPHA) * val
        if val is not None:
            stop_ewma[(sid, gob)] = val
    return stop_ewma

sys.path.insert(0, os.path.dirname(__file__))
import analyze as az

MAPBOX_TOKEN = "pk.eyJ1IjoidGltNzE3OSIsImEiOiJjbW9uc2JtZDIwdHlwMnFzNGljdzhsdWc5In0.nwdmWTPiKEjJvnn1boLXwg"
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

ROUTES = {
    "taipei": {
        "label":      "台北市",
        "snap_pats":  ["eta_snapshots_taipei_{date}.csv",
                       "eta_snapshots_{date}.csv"],
        "stops_pat":  "city_stops_taipei_{date}.json",
        "shapes_pat": "city_shapes_taipei_{date}.json",
        "center":     [121.540, 25.043],
    },
    "newtaipei": {
        "label":      "新北市",
        "snap_pats":  ["eta_snapshots_newtaipei_{date}.csv",
                       "eta_snapshots_857_{date}.csv"],
        "stops_pat":  "city_stops_newtaipei_{date}.json",
        "shapes_pat": "city_shapes_newtaipei_{date}.json",
        "center":     [121.460, 25.040],
    },
}

# ── 顏色函數：絕對誤差 ───────────────────────────────────────────────────────

def err_to_color(e):
    if e is None: return "#bbbbbb"
    if e <= 0:    return "#34A853"
    if e <= 30:   return "#FBBC04"
    if e <= 60:   return "#EA8600"
    if e <= 120:  return "#EA4335"
    return "#A50B0B"

def err_label(e):
    if e is None: return "無資料"
    if e <= 0:    return f"{e:+.0f}s 暢通"
    if e <= 30:   return f"+{e:.0f}s 輕微"
    if e <= 60:   return f"+{e:.0f}s 中度"
    if e <= 120:  return f"+{e:.0f}s 嚴重"
    return f"+{e:.0f}s 極嚴重"


# ── 顏色函數：路段增量 Δerror ────────────────────────────────────────────────

def delta_to_color(d):
    if d is None: return "#bbbbbb"
    if d <= 0:    return "#34A853"   # 此段比預測快
    if d <= 15:   return "#FBBC04"   # 輕微增量
    if d <= 40:   return "#EA8600"   # 中度
    if d <= 80:   return "#EA4335"   # 嚴重
    return "#A50B0B"                 # 極嚴重

def delta_label(d):
    if d is None: return "無資料"
    if d <= 0:    return f"{d:+.0f}s 此段快於預測"
    if d <= 15:   return f"Δ+{d:.0f}s 輕微增量"
    if d <= 40:   return f"Δ+{d:.0f}s 中度增量"
    if d <= 80:   return f"Δ+{d:.0f}s 嚴重增量"
    return f"Δ+{d:.0f}s 極嚴重增量"


# ── GeoJSON 建構 ─────────────────────────────────────────────────────────────

def build_segments_geojson(stop_map, stop_errors, raw_stops, shape_map=None):
    """絕對誤差地圖：每路段顏色 = 兩端點 mean_err 平均；有 shape 則沿路線幾何畫"""
    features = []
    for entry in raw_stops:
        gob = str(entry.get("Direction"))
        rkey = str(entry.get("RouteUID") or entry.get("RouteID", ""))
        shape_coords = shape_map.get((rkey, gob)) if shape_map else None

        stops_sorted = sorted(entry["Stops"], key=lambda s: s["StopSequence"])
        for i in range(len(stops_sorted) - 1):
            s_a, s_b = stops_sorted[i], stops_sorted[i + 1]
            sid_a, sid_b = str(s_a["StopID"]), str(s_b["StopID"])
            pos_a = s_a.get("StopPosition", {})
            pos_b = s_b.get("StopPosition", {})
            lon_a, lat_a = pos_a.get("PositionLon"), pos_a.get("PositionLat")
            lon_b, lat_b = pos_b.get("PositionLon"), pos_b.get("PositionLat")
            if not all([lon_a, lat_a, lon_b, lat_b]):
                continue

            errs_a = stop_errors.get((sid_a, gob))
            errs_b = stop_errors.get((sid_b, gob))
            mean_a = sum(errs_a) / len(errs_a) if errs_a else None
            mean_b = sum(errs_b) / len(errs_b) if errs_b else None
            if mean_a is not None and mean_b is not None:
                seg_err = (mean_a + mean_b) / 2
            else:
                seg_err = mean_a if mean_a is not None else mean_b

            if seg_err is None:       # 完全無資料的路段跳過（省空間）
                continue

            # 路線幾何：有 shape 沿道路，否則直線
            coords = get_subpath(shape_coords, lon_a, lat_a, lon_b, lat_b) \
                     if shape_coords else [[lon_a, lat_a], [lon_b, lat_b]]

            direction = "去程" if gob == "0" else ("回程" if gob == "1" else "不分向")
            features.append({
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": coords},
                "properties": {
                    "seg_id":    f"{sid_a}-{sid_b}",
                    "from_name": s_a["StopName"]["Zh_tw"],
                    "to_name":   s_b["StopName"]["Zh_tw"],
                    "direction": direction,
                    "seg_err":   round(seg_err, 1) if seg_err is not None else None,
                    "color":     err_to_color(seg_err),
                    "label":     err_label(seg_err),
                    "n_samples": (len(errs_a) if errs_a else 0) + (len(errs_b) if errs_b else 0),
                    "has_shape": shape_coords is not None,
                },
            })
    return {"type": "FeatureCollection", "features": features}


def build_delta_segments_geojson(seg_deltas, stop_errors, raw_stops, shape_map=None):
    """
    Δerror 地圖：
      - 有 Δerror 資料 → 用 delta 著色（has_delta=true，不透明）
      - 只有絕對誤差  → fallback 到 abs error（has_delta=false，半透明）
      - 完全無資料    → 灰色
    有 shape_map 則沿路線幾何畫，否則直線。
    """
    features = []
    for entry in raw_stops:
        gob = str(entry.get("Direction"))
        rkey = str(entry.get("RouteUID") or entry.get("RouteID", ""))
        shape_coords = shape_map.get((rkey, gob)) if shape_map else None

        stops_sorted = sorted(entry["Stops"], key=lambda s: s["StopSequence"])
        for i in range(len(stops_sorted) - 1):
            s_a, s_b = stops_sorted[i], stops_sorted[i + 1]
            sid_a, sid_b = str(s_a["StopID"]), str(s_b["StopID"])
            pos_a = s_a.get("StopPosition", {})
            pos_b = s_b.get("StopPosition", {})
            lon_a, lat_a = pos_a.get("PositionLon"), pos_a.get("PositionLat")
            lon_b, lat_b = pos_b.get("PositionLon"), pos_b.get("PositionLat")
            if not all([lon_a, lat_a, lon_b, lat_b]):
                continue

            key = (gob, sid_a, sid_b)
            deltas = seg_deltas.get(key)

            if deltas:
                # ── 精確 Δerror ──
                mean_d    = round(sum(deltas) / len(deltas), 1)
                has_delta = True
                color     = delta_to_color(mean_d)
                label     = delta_label(mean_d)
                n_samples = len(deltas)
                seg_err   = mean_d
            else:
                # ── Fallback：絕對誤差（半透明）──
                errs_a = stop_errors.get((sid_a, gob))
                errs_b = stop_errors.get((sid_b, gob))
                ma = sum(errs_a) / len(errs_a) if errs_a else None
                mb = sum(errs_b) / len(errs_b) if errs_b else None
                if ma is not None or mb is not None:
                    abs_err = ((ma or 0) + (mb or 0)) / (int(ma is not None) + int(mb is not None))
                    abs_err = round(abs_err, 1)
                    has_delta = False
                    color     = err_to_color(abs_err)
                    label     = f"(累積誤差) {err_label(abs_err)}"
                    n_samples = (len(errs_a) if errs_a else 0) + (len(errs_b) if errs_b else 0)
                    seg_err   = abs_err
                else:
                    continue          # 完全無資料跳過

            # 路線幾何：有 shape 沿道路，否則直線
            coords = get_subpath(shape_coords, lon_a, lat_a, lon_b, lat_b) \
                     if shape_coords else [[lon_a, lat_a], [lon_b, lat_b]]

            direction = "去程" if gob == "0" else ("回程" if gob == "1" else "不分向")
            features.append({
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": coords},
                "properties": {
                    "seg_id":    f"{sid_a}-{sid_b}",
                    "from_name": s_a["StopName"]["Zh_tw"],
                    "to_name":   s_b["StopName"]["Zh_tw"],
                    "direction": direction,
                    "seg_err":   seg_err,
                    "color":     color,
                    "label":     label,
                    "has_delta": has_delta,
                    "n_samples": n_samples,
                    "has_shape": shape_coords is not None,
                },
            })
    return {"type": "FeatureCollection", "features": features}


def build_segments_geojson_advanced(stop_map, stop_errors, stop_ewma, raw_stops,
                                     shape_map=None):
    """
    進階版絕對誤差地圖：
      - EWMA 時間衰減（越近期事件權重越高）
      - Sequence-aware shape matching（減少 sub-route mismatch）
    """
    features = []
    for entry in raw_stops:
        gob = str(entry.get("Direction"))
        rkey = str(entry.get("RouteUID") or entry.get("RouteID", ""))
        shape_coords = shape_map.get((rkey, gob)) if shape_map else None

        stops_sorted = sorted(entry["Stops"], key=lambda s: s["StopSequence"])
        n_stops = len(stops_sorted)

        for i in range(n_stops - 1):
            s_a, s_b = stops_sorted[i], stops_sorted[i + 1]
            sid_a, sid_b = str(s_a["StopID"]), str(s_b["StopID"])
            pos_a = s_a.get("StopPosition", {})
            pos_b = s_b.get("StopPosition", {})
            lon_a, lat_a = pos_a.get("PositionLon"), pos_a.get("PositionLat")
            lon_b, lat_b = pos_b.get("PositionLon"), pos_b.get("PositionLat")
            if not all([lon_a, lat_a, lon_b, lat_b]):
                continue

            # EWMA 優先；無 EWMA 時 fallback 到簡單平均
            mean_a = stop_ewma.get((sid_a, gob))
            mean_b = stop_ewma.get((sid_b, gob))
            if mean_a is None:
                ea = stop_errors.get((sid_a, gob))
                mean_a = sum(ea) / len(ea) if ea else None
            if mean_b is None:
                eb = stop_errors.get((sid_b, gob))
                mean_b = sum(eb) / len(eb) if eb else None

            if mean_a is not None and mean_b is not None:
                seg_err = (mean_a + mean_b) / 2
            else:
                seg_err = mean_a if mean_a is not None else mean_b
            if seg_err is None:
                continue

            # Sequence-aware shape matching
            if shape_coords:
                sf_a = i / max(n_stops - 1, 1)
                sf_b = (i + 1) / max(n_stops - 1, 1)
                coords = get_subpath_seq(shape_coords,
                                         lon_a, lat_a, lon_b, lat_b, sf_a, sf_b)
            else:
                coords = [[lon_a, lat_a], [lon_b, lat_b]]

            n_a = len(stop_errors.get((sid_a, gob), []))
            n_b = len(stop_errors.get((sid_b, gob), []))
            direction = "去程" if gob == "0" else ("回程" if gob == "1" else "不分向")
            features.append({
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": coords},
                "properties": {
                    "seg_id":    f"{sid_a}-{sid_b}",
                    "from_name": s_a["StopName"]["Zh_tw"],
                    "to_name":   s_b["StopName"]["Zh_tw"],
                    "direction": direction,
                    "seg_err":   round(seg_err, 1),
                    "color":     err_to_color(seg_err),
                    "label":     err_label(seg_err),
                    "n_samples": n_a + n_b,
                    "has_shape": shape_coords is not None,
                },
            })
    return {"type": "FeatureCollection", "features": features}


def build_delta_segments_geojson_advanced(seg_deltas, stop_errors, stop_ewma,
                                           raw_stops, shape_map=None):
    """
    進階版 Δerror 地圖：EWMA fallback + sequence-aware shape matching。
    """
    features = []
    for entry in raw_stops:
        gob = str(entry.get("Direction"))
        rkey = str(entry.get("RouteUID") or entry.get("RouteID", ""))
        shape_coords = shape_map.get((rkey, gob)) if shape_map else None

        stops_sorted = sorted(entry["Stops"], key=lambda s: s["StopSequence"])
        n_stops = len(stops_sorted)

        for i in range(n_stops - 1):
            s_a, s_b = stops_sorted[i], stops_sorted[i + 1]
            sid_a, sid_b = str(s_a["StopID"]), str(s_b["StopID"])
            pos_a = s_a.get("StopPosition", {})
            pos_b = s_b.get("StopPosition", {})
            lon_a, lat_a = pos_a.get("PositionLon"), pos_a.get("PositionLat")
            lon_b, lat_b = pos_b.get("PositionLon"), pos_b.get("PositionLat")
            if not all([lon_a, lat_a, lon_b, lat_b]):
                continue

            key = (gob, sid_a, sid_b)
            deltas = seg_deltas.get(key)

            if deltas:
                mean_d    = round(sum(deltas) / len(deltas), 1)
                has_delta = True
                color     = delta_to_color(mean_d)
                label     = delta_label(mean_d)
                n_samples = len(deltas)
                seg_err   = mean_d
            else:
                # Fallback：EWMA 誤差（比簡單平均更即時）
                ma = stop_ewma.get((sid_a, gob))
                mb = stop_ewma.get((sid_b, gob))
                if ma is None:
                    ea = stop_errors.get((sid_a, gob))
                    ma = sum(ea) / len(ea) if ea else None
                if mb is None:
                    eb = stop_errors.get((sid_b, gob))
                    mb = sum(eb) / len(eb) if eb else None

                if ma is not None or mb is not None:
                    abs_err = ((ma or 0) + (mb or 0)) / (
                        int(ma is not None) + int(mb is not None))
                    abs_err   = round(abs_err, 1)
                    has_delta = False
                    color     = err_to_color(abs_err)
                    label     = f"(累積誤差/EWMA) {err_label(abs_err)}"
                    n_samples = (len(stop_errors.get((sid_a, gob), [])) +
                                 len(stop_errors.get((sid_b, gob), [])))
                    seg_err   = abs_err
                else:
                    continue

            # Sequence-aware shape matching
            if shape_coords:
                sf_a = i / max(n_stops - 1, 1)
                sf_b = (i + 1) / max(n_stops - 1, 1)
                coords = get_subpath_seq(shape_coords,
                                         lon_a, lat_a, lon_b, lat_b, sf_a, sf_b)
            else:
                coords = [[lon_a, lat_a], [lon_b, lat_b]]

            direction = "去程" if gob == "0" else ("回程" if gob == "1" else "不分向")
            features.append({
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": coords},
                "properties": {
                    "seg_id":    f"{sid_a}-{sid_b}",
                    "from_name": s_a["StopName"]["Zh_tw"],
                    "to_name":   s_b["StopName"]["Zh_tw"],
                    "direction": direction,
                    "seg_err":   seg_err,
                    "color":     color,
                    "label":     label,
                    "has_delta": has_delta,
                    "n_samples": n_samples,
                    "has_shape": shape_coords is not None,
                },
            })
    return {"type": "FeatureCollection", "features": features}


def build_stops_geojson(stop_map, stop_errors, groups):
    """小圓點，zoom >= 13 顯示。只輸出有 arrival event 的站（省空間）。"""
    features = []
    for (sid, gob), pts in groups.items():
        errs = stop_errors.get((sid, gob))
        if not errs:
            continue                   # 無 arrival event → 跳過，省 GeoJSON 大小
        info = stop_map.get(sid, {})
        if not info.get("lon"):
            continue
        mean_err = round(sum(errs) / len(errs), 1)
        direction = "去程" if gob == "0" else ("回程" if gob == "1" else "不分向")
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [info["lon"], info["lat"]]},
            "properties": {
                "sid": sid, "gob": gob,
                "name": info["name"], "seq": info["seq"],
                "direction": direction,
                "mean_err":  mean_err,
                "n_events":  len(errs) if errs else 0,
                "label":     err_label(mean_err),
            },
        })
    return {"type": "FeatureCollection", "features": features}


# ── HTML 模板（共用框架，legend 內容由參數注入）──────────────────────────────

HTML_TEMPLATE = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>__TITLE__</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://api.mapbox.com/mapbox-gl-js/v3.3.0/mapbox-gl.js"></script>
<link href="https://api.mapbox.com/mapbox-gl-js/v3.3.0/mapbox-gl.css" rel="stylesheet">
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: -apple-system, "Helvetica Neue", sans-serif; background:#f5f5f5; }
#map { position:absolute; top:0; bottom:0; width:100%; }
#legend {
  position:absolute; bottom:32px; left:12px;
  background:#fff; padding:14px 18px; border-radius:12px;
  font-size:13px; line-height:2; box-shadow:0 2px 10px rgba(0,0,0,.18);
  min-width:210px;
}
#legend h4 { font-size:14px; font-weight:700; margin-bottom:4px; color:#333; }
#legend .ts { font-size:11px; color:#888; margin-bottom:8px; }
.leg-row { display:flex; align-items:center; gap:8px; color:#444; }
.leg-line { width:32px; height:5px; border-radius:3px; flex-shrink:0; }
#tooltip {
  position:absolute; top:14px; right:14px;
  background:#fff; padding:12px 16px; border-radius:10px;
  font-size:13px; min-width:220px; display:none;
  box-shadow:0 2px 10px rgba(0,0,0,.18); pointer-events:none;
}
#tooltip h4 { font-size:14px; margin-bottom:3px; color:#222; }
#tooltip .sub { color:#666; font-size:12px; }
#tooltip .err { font-size:18px; font-weight:700; margin-top:4px; }
#tooltip .nsam { font-size:11px; color:#999; margin-top:2px; }
</style>
</head>
<body>
<div id="map"></div>

<div id="legend">
  <h4>__LEGEND_TITLE__</h4>
  <div class="ts">🕐 __TIMESTAMP__</div>
__LEGEND_ROWS__
</div>

<div id="tooltip">
  <h4 id="tt-title"></h4>
  <div class="sub" id="tt-sub"></div>
  <div class="err" id="tt-err"></div>
  <div class="nsam" id="tt-nsam"></div>
</div>

<script>
mapboxgl.accessToken = '__TOKEN__';
const map = new mapboxgl.Map({
  container: 'map',
  style: 'mapbox://styles/mapbox/light-v11',
  center: __CENTER__,
  zoom: 12.5
});

const SEGS  = __SEGS_GEOJSON__;
const STOPS = __STOPS_GEOJSON__;

map.on('load', () => {
  map.addSource('segs', { type:'geojson', data: SEGS });
  map.addLayer({
    id:'seg-casing', type:'line', source:'segs',
    layout:{ 'line-join':'round', 'line-cap':'round' },
    paint:{
      'line-color':'#fff',
      'line-width':[ 'interpolate',['linear'],['zoom'], 10,8, 15,14 ],
      'line-opacity': ['case', ['get','has_delta'], 0.6, 0.3],
    }
  });
  map.addLayer({
    id:'seg-line', type:'line', source:'segs',
    layout:{ 'line-join':'round', 'line-cap':'round' },
    paint:{
      'line-color': ['get','color'],
      'line-width':[ 'interpolate',['linear'],['zoom'], 10,5, 15,10 ],
      'line-opacity': ['case', ['get','has_delta'], 1.0, 0.45],
    }
  });

  map.addSource('stops', { type:'geojson', data: STOPS });
  map.addLayer({
    id:'stop-dot', type:'circle', source:'stops',
    minzoom: 13,
    paint:{
      'circle-radius': 5, 'circle-color':'#fff',
      'circle-stroke-width': 2, 'circle-stroke-color':'#555',
    }
  });
  map.addLayer({
    id:'stop-label', type:'symbol', source:'stops',
    minzoom: 14,
    layout:{
      'text-field': ['get','name'], 'text-size': 11,
      'text-offset': [0, 1.3], 'text-anchor': 'top',
    },
    paint:{
      'text-color':'#222', 'text-halo-color':'#fff', 'text-halo-width': 1.5,
    }
  });

  const tt      = document.getElementById('tooltip');
  const ttTitle = document.getElementById('tt-title');
  const ttSub   = document.getElementById('tt-sub');
  const ttErr   = document.getElementById('tt-err');
  const ttNsam  = document.getElementById('tt-nsam');

  function showSeg(p) {
    ttTitle.textContent = `${p.from_name} → ${p.to_name}`;
    const dtype = (p.has_delta === true || p.has_delta === 'true') ? '🎯 Δerror' : '(累積誤差)';
    ttSub.textContent   = `${p.route || ''}  ${p.direction}  ${dtype}`;
    ttErr.style.color   = p.color;
    const v = p.seg_err;
    ttErr.textContent   = v !== null ? (v > 0 ? `+${v}s` : `${v}s`) + `  ${p.label}` : '無資料';
    ttNsam.textContent  = p.n_samples > 0 ? `（${p.n_samples} 筆）` : '';
    tt.style.display = 'block';
  }
  map.on('mousemove', 'seg-line', (e) => {
    map.getCanvas().style.cursor = 'pointer';
    showSeg(e.features[0].properties);
  });
  map.on('mouseleave', 'seg-line', () => {
    map.getCanvas().style.cursor = '';
    tt.style.display = 'none';
  });
  map.on('mousemove', 'stop-dot', (e) => {
    map.getCanvas().style.cursor = 'pointer';
    const p = e.features[0].properties;
    ttTitle.textContent = p.name;
    ttSub.textContent   = `${p.direction}・Seq ${p.seq}`;
    ttErr.style.color   = '#333';
    ttErr.textContent   = p.mean_err !== null ? `${p.label}（${p.n_events}筆）` : '無到站資料';
    ttNsam.textContent  = '';
    tt.style.display = 'block';
  });
  map.on('mouseleave', 'stop-dot', () => {
    map.getCanvas().style.cursor = '';
    tt.style.display = 'none';
  });
  map.on('click', 'seg-line', (e) => {
    const p = e.features[0].properties;
    new mapboxgl.Popup()
      .setLngLat(e.lngLat)
      .setHTML(`<b>${p.from_name} → ${p.to_name}</b><br>${p.direction}<br>${p.label}${p.n_samples>0?' ('+p.n_samples+'筆)':''}`)
      .addTo(map);
  });
  map.on('click', 'stop-dot', (e) => {
    const p = e.features[0].properties;
    new mapboxgl.Popup()
      .setLngLat(e.lngLat)
      .setHTML(`<b>${p.name}</b><br>${p.direction}・Seq ${p.seq}<br>${p.label}`)
      .addTo(map);
  });
});
</script>
</body>
</html>
"""

LEGEND_ROWS_ABS = """\
  <div class="leg-row"><div class="leg-line" style="background:#34A853"></div>暢通（≤0s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#FBBC04"></div>輕微（+1~30s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#EA8600"></div>中度（+31~60s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#EA4335"></div>嚴重（+61~120s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#A50B0B"></div>極嚴重（>120s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#bbb"></div>無資料</div>"""

LEGEND_ROWS_DELTA = """\
  <div class="leg-row"><div class="leg-line" style="background:#34A853"></div>此段快於預測（Δ≤0s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#FBBC04"></div>輕微增量（Δ+1~15s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#EA8600"></div>中度增量（Δ+16~40s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#EA4335"></div>嚴重增量（Δ+41~80s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#A50B0B"></div>極嚴重增量（Δ>80s）</div>
  <div class="leg-row"><div class="leg-line" style="background:#bbb"></div>無資料</div>
  <div style="margin-top:6px;font-size:11px;color:#888">不透明 = Δerror 精確路段<br>半透明 = 累積誤差 fallback</div>"""


# ── 路線載入 ──────────────────────────────────────────────────────────────────

def load_route(route_key, date, data_dir, hours=3.0):
    """
    回傳 (raw_stops, stop_map, stop_errors, groups, all_results, shape_map)
    all_results 是帶名稱 / seq 的完整 arrival event 列表，供 compute_segment_deltas 使用。
    shape_map: {(route_key, direction_str): [[lon, lat], ...]}，可能為空 dict
    hours: 只讀最近 N 小時（0 = 全部）
    """
    from datetime import timedelta
    cfg = ROUTES[route_key]

    # 支援多個 snap_pats，取第一個存在的
    snap_path = None
    for pat in cfg.get("snap_pats", [cfg.get("snap_pat", "")]):
        candidate = os.path.join(data_dir, pat.format(date=date))
        if os.path.exists(candidate):
            snap_path = candidate
            break

    stops_path = os.path.join(data_dir, cfg["stops_pat"].format(date=date))

    if not snap_path or not os.path.exists(stops_path):
        print(f"  [{route_key}] 找不到資料，跳過")
        return None, None, None, None, None, {}

    with open(stops_path) as f:
        raw_stops = json.load(f)

    stop_map = {}
    for entry in raw_stops:
        d = entry.get("Direction")
        for s in entry.get("Stops", []):
            sid = str(s["StopID"])
            pos = s.get("StopPosition", {})
            stop_map[sid] = {
                "name": s["StopName"]["Zh_tw"],
                "dir":  d,
                "seq":  s["StopSequence"],
                "lon":  pos.get("PositionLon"),
                "lat":  pos.get("PositionLat"),
            }

    since = (datetime.now() - __import__('datetime').timedelta(hours=hours)
             if hours > 0 else None)
    groups      = az.load_snapshots(snap_path, since=since)
    stop_errors = defaultdict(list)
    all_results = []

    for (sid, gob), pts in groups.items():
        info = stop_map.get(sid, {})
        for r in az.analyze_stop(pts):
            r["sid"]  = sid
            r["gob"]  = gob
            r["name"] = info.get("name", f"?{sid}")
            r["seq"]  = info.get("seq", 0)
            stop_errors[(sid, gob)].append(r["error_s"])
            all_results.append(r)

    # ── 路線幾何（shape）──
    shapes_pat  = cfg.get("shapes_pat", "")
    shapes_path = os.path.join(data_dir, shapes_pat.format(date=date)) if shapes_pat else ""
    shape_map   = load_shapes(shapes_path, route_key)
    n_shapes    = len(shape_map)
    print(f"    shape: {n_shapes} 條（{'✓' if n_shapes else '✗ 無 shape 資料，退化為直線'}）")

    # ── EWMA 時間衰減誤差 ──
    stop_ewma = compute_ewma(all_results)

    return raw_stops, stop_map, stop_errors, groups, all_results, shape_map, stop_ewma


# ── 主程式 ────────────────────────────────────────────────────────────────────

def render_html(segs_gj, stops_gj, center, ts,
                title, legend_title, legend_rows):
    cx, cy = center
    return (HTML_TEMPLATE
            .replace("__TOKEN__",        MAPBOX_TOKEN)
            .replace("__TITLE__",        title)
            .replace("__LEGEND_TITLE__", legend_title)
            .replace("__LEGEND_ROWS__",  legend_rows)
            .replace("__SEGS_GEOJSON__", json.dumps(segs_gj))
            .replace("__STOPS_GEOJSON__",json.dumps(stops_gj))
            .replace("__TIMESTAMP__",    ts)
            .replace("__CENTER__",       f"[{cx:.3f}, {cy:.3f}]"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date",  default=datetime.now().strftime("%Y%m%d"))
    parser.add_argument("--dir",   default=DATA_DIR)
    parser.add_argument("--hours", type=float, default=3.0,
                        help="只用最近 N 小時的資料（預設 3）")
    parser.add_argument("--out",          default=os.path.join(os.path.dirname(__file__), "map.html"))
    parser.add_argument("--out-delta",    default=os.path.join(os.path.dirname(__file__), "map-delta.html"))
    parser.add_argument("--out-advanced", default=os.path.join(os.path.dirname(__file__), "map-advanced.html"))
    args = parser.parse_args()

    all_segs_abs      = []
    all_segs_delta    = []
    all_segs_adv      = []   # advanced: EWMA abs
    all_segs_adv_d    = []   # advanced: EWMA delta
    all_stops         = []
    centers           = []

    for route_key in ROUTES:
        raw_stops, stop_map, stop_errors, groups, all_results, shape_map, stop_ewma = \
            load_route(route_key, args.date, args.dir, hours=args.hours)
        if raw_stops is None:
            continue

        label = ROUTES[route_key]["label"]

        # ── 絕對誤差路段 ──
        segs_abs = build_segments_geojson(stop_map, stop_errors, raw_stops,
                                          shape_map=shape_map)
        for f in segs_abs["features"]:
            f["properties"]["route"] = label
        all_segs_abs.extend(segs_abs["features"])

        # ── Δerror 路段 ──
        seg_deltas, _ = az.compute_segment_deltas(all_results)
        segs_delta = build_delta_segments_geojson(seg_deltas, stop_errors, raw_stops,
                                                   shape_map=shape_map)
        for f in segs_delta["features"]:
            f["properties"]["route"] = label
        all_segs_delta.extend(segs_delta["features"])

        # ── 進階路段（EWMA + seq-aware shape）──
        segs_adv = build_segments_geojson_advanced(
            stop_map, stop_errors, stop_ewma, raw_stops, shape_map=shape_map)
        for f in segs_adv["features"]:
            f["properties"]["route"] = label
        all_segs_adv.extend(segs_adv["features"])

        segs_adv_d = build_delta_segments_geojson_advanced(
            seg_deltas, stop_errors, stop_ewma, raw_stops, shape_map=shape_map)
        for f in segs_adv_d["features"]:
            f["properties"]["route"] = label
        all_segs_adv_d.extend(segs_adv_d["features"])

        # ── 站點（共用） ──
        stops_gj = build_stops_geojson(stop_map, stop_errors, groups)
        for f in stops_gj["features"]:
            f["properties"]["route"] = label
        all_stops.extend(stops_gj["features"])
        centers.append(ROUTES[route_key]["center"])

        n_abs   = sum(1 for f in segs_abs["features"]
                      if f["properties"]["seg_err"] is not None
                      and f["properties"]["seg_err"] > 60)
        n_delta = sum(1 for f in segs_delta["features"]
                      if f["properties"]["seg_err"] is not None
                      and f["properties"]["seg_err"] > 40)
        n_delta_has = sum(1 for f in segs_delta["features"]
                          if f["properties"]["seg_err"] is not None)
        n_ewma  = sum(1 for f in segs_adv["features"]
                      if f["properties"]["seg_err"] is not None
                      and f["properties"]["seg_err"] > 60)
        print(f"  {label}: "
              f"abs路段 {len(segs_abs['features'])} (壅塞>{n_abs}), "
              f"delta路段有資料 {n_delta_has} (增量>{n_delta}), "
              f"adv路段 {len(segs_adv['features'])} (EWMA壅塞>{n_ewma}), "
              f"站點 {len(stops_gj['features'])}")

    if not all_segs_abs:
        print("沒有可用資料"); return

    cx = sum(c[0] for c in centers) / len(centers)
    cy = sum(c[1] for c in centers) / len(centers)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    combined_stops = {"type": "FeatureCollection", "features": all_stops}

    # ── 輸出 map.html（絕對誤差）──
    html_abs = render_html(
        segs_gj      = {"type": "FeatureCollection", "features": all_segs_abs},
        stops_gj     = combined_stops,
        center       = (cx, cy),
        ts           = ts,
        title        = "公車路線即時壅塞地圖（絕對誤差）",
        legend_title = "公車路線壅塞（累積誤差）",
        legend_rows  = LEGEND_ROWS_ABS,
    )
    with open(args.out, "w") as f:
        f.write(html_abs)
    print(f"\n✅ map.html      → {args.out}  ({len(all_segs_abs)} 路段)")

    # ── 輸出 map-delta.html（Δerror）──
    html_delta = render_html(
        segs_gj      = {"type": "FeatureCollection", "features": all_segs_delta},
        stops_gj     = combined_stops,
        center       = (cx, cy),
        ts           = ts,
        title        = "公車路線路段增量地圖（Δerror）",
        legend_title = "路段壅塞增量（Δerror）",
        legend_rows  = LEGEND_ROWS_DELTA,
    )
    with open(args.out_delta, "w") as f:
        f.write(html_delta)
    print(f"✅ map-delta.html → {args.out_delta}  ({len(all_segs_delta)} 路段)")

    # ── 輸出 map-advanced.html（EWMA + seq-aware shape，以 delta 版為底）──
    LEGEND_ROWS_ADVANCED = LEGEND_ROWS_DELTA.replace(
        "不透明 = Δerror 精確路段<br>半透明 = 累積誤差 fallback",
        "不透明 = Δerror 精確路段<br>半透明 = EWMA 累積誤差 fallback<br>"
        "<span style='color:#aaa'>EWMA α=0.35 · median predicted · RouteUID grouping</span>"
    )
    html_adv = render_html(
        segs_gj      = {"type": "FeatureCollection", "features": all_segs_adv_d},
        stops_gj     = combined_stops,
        center       = (cx, cy),
        ts           = ts,
        title        = "公車路況壅塞地圖（進階算法）",
        legend_title = "路段壅塞增量（EWMA + seq-aware）",
        legend_rows  = LEGEND_ROWS_ADVANCED,
    )
    with open(args.out_advanced, "w") as f:
        f.write(html_adv)
    print(f"✅ map-advanced.html → {args.out_advanced}  ({len(all_segs_adv_d)} 路段)")


if __name__ == "__main__":
    main()
