"""
ETA 預測誤差分析腳本 — 讀 raw eta_snapshots_*.csv，套過濾邏輯，輸出壅塞訊號。

Filter 規則（不動 raw data）：
  F1. blob 凍結：相鄰兩點 ETA 完全相同 → 跳過，不更新 bus_start
  F2. 大幅跳降 = 換車：ETA 在一輪內減少 > SWAP_DROP_S (135s) → 更新 bus_start
  F3. 任意跳升 = 換車：ETA 上升 > SWAP_RISE_RATIO (50%) 且 prev_eta > MIN_ETA_FOR_SWAP (30s) → 更新 bus_start

Arrival event 條件（乾淨的）：
  - prev_eta < ARR_LOW (120s) AND cur_eta > ARR_HIGH (200s)
  - bus_start 到 prev 之間，沒有任何 F1/F2/F3 觸發過（即這段 ETA 是同一班車、穩定倒數）

用法：
  python3 analyze.py [--date YYYYMMDD] [--dir /path/to/data]
"""

import csv, json, argparse, os
from datetime import datetime
from collections import defaultdict

# ── 參數 ────────────────────────────────────────────────────────────────────
POLL_INTERVAL_S     = 90
SWAP_DROP_S         = int(POLL_INTERVAL_S * 1.5)   # 135s：大幅跳降判換車
SWAP_RISE_RATIO     = 0.5                           # 上升 > 50%：判換車
MIN_ETA_FOR_SWAP    = 30                            # ETA 太小時不判換車（誤差範圍）
ARR_LOW             = 120                           # arrival event：到站前閾值
ARR_HIGH            = 200                           # arrival event：換車後跳升閾值
MIN_CLEAN_POLLS     = 2                             # 至少要有 N 個乾淨 poll 才算有效事件


def load_stops(bus_stops_json):
    """載入 StopID → {name, dir, seq}"""
    with open(bus_stops_json) as f:
        raw = json.load(f)
    m = {}
    for entry in raw:
        d = entry.get("Direction")
        for s in entry.get("Stops", []):
            m[str(s["StopID"])] = {
                "name": s["StopName"]["Zh_tw"],
                "dir": d,
                "seq": s["StopSequence"],
            }
    return m


def load_snapshots(csv_path, since=None):
    """
    載入 eta_snapshots CSV，回傳依 (StopID, GoBack) 分組的時序列表。
    since: datetime，只讀取 >= since 的資料（用於 --hours 限制窗口）。
    """
    groups = defaultdict(list)
    with open(csv_path) as f:
        for r in csv.DictReader(f):
            if since:
                try:
                    row_ts = datetime.strptime(r["timestamp"], "%Y-%m-%d %H:%M:%S")
                except ValueError:
                    continue
                if row_ts < since:
                    continue
            key = (r["StopID"], r["GoBack"])
            groups[key].append({
                "ts":        datetime.strptime(r["timestamp"], "%Y-%m-%d %H:%M:%S"),
                "eta":       int(r["EstimateTime_s"]),
                "route_uid": r.get("RouteUID", ""),   # 供 Δerror 分組用
            })
    for pts in groups.values():
        pts.sort(key=lambda x: x["ts"])
    return groups


def classify_transition(prev_eta, cur_eta):
    """
    回傳 transition 類型：
      'freeze'   — F1 blob 凍結
      'swap_drop' — F2 大幅跳降（換車）
      'swap_rise' — F3 跳升（換車）
      'normal'   — 正常倒數
      'arrival'  — 到站事件（低→高大跳升）
    """
    delta = cur_eta - prev_eta
    if delta == 0:
        return "freeze"
    if delta > 0:
        # 跳升
        if prev_eta < ARR_LOW and cur_eta > ARR_HIGH:
            return "arrival"
        if prev_eta > MIN_ETA_FOR_SWAP and (delta / prev_eta) > SWAP_RISE_RATIO:
            return "swap_rise"
        return "normal"
    else:
        # 跳降
        if abs(delta) > SWAP_DROP_S:
            return "swap_drop"
        return "normal"


def analyze_stop(pts):
    """
    給定一個站的 ETA 時序，偵測乾淨的 arrival event，回傳誤差列表。
    每個元素：{"error_s", "predicted_ts", "actual_ts", "bus_start_ts",
              "bus_start_eta", "n_clean_polls", "events"}
    """
    results = []
    bus_start_idx = 0
    clean_polls   = 0   # 目前這班車的乾淨 poll 數
    dirty         = False  # 這班車有沒有被 F1/F2/F3 污染

    for i in range(1, len(pts)):
        prev, cur = pts[i - 1], pts[i]
        t = classify_transition(prev["eta"], cur["eta"])

        if t == "arrival":
            if not dirty and clean_polls >= MIN_CLEAN_POLLS:
                start = pts[bus_start_idx]
                # ── 改進 1：median predicted arrival（比第一個樣本穩定）──
                # clean window = bus_start_idx..i-1，每一點都能算一個預測到站時間
                pred_times = sorted(
                    pts[j]["ts"].timestamp() + pts[j]["eta"]
                    for j in range(bus_start_idx, i)
                )
                predicted = pred_times[len(pred_times) // 2]   # 取 median
                actual    = prev["ts"].timestamp() + prev["eta"]
                results.append({
                    "error_s":        actual - predicted,
                    "predicted_ts":   datetime.fromtimestamp(predicted),
                    "actual_ts":      datetime.fromtimestamp(actual),
                    "bus_start_ts":   start["ts"],
                    "bus_start_eta":  start["eta"],
                    "n_clean_polls":  clean_polls,
                    "route_uid":      pts[bus_start_idx].get("route_uid", ""),
                })
            # 換下一班，從 cur 重新開始
            bus_start_idx = i
            clean_polls   = 0
            dirty         = False

        elif t in ("swap_drop", "swap_rise"):
            # 換車，重設 bus_start
            bus_start_idx = i
            clean_polls   = 0
            dirty         = False

        elif t == "freeze":
            # blob 凍結：這輪不計入 clean poll，且標記 dirty
            dirty = True

        else:  # normal
            clean_polls += 1

    return results


MAX_SEQ_GAP = 6   # 相鄰站 seq 差超過這個就不算同一路段


def compute_segment_deltas(all_results):
    """
    對同一班車（相同 gob + bus_start_ts）追蹤到的相鄰站，計算 Δerror。
    Δerror = error_B - error_A = 實際旅行時間(A→B) - 預測旅行時間(A→B)
    回傳 dict: (gob, sid_a, sid_b) → list of delta_s
    """
    # ── 改進 2：加 route_uid 避免不同路線的公車被誤判為同一班 ──
    trips = defaultdict(list)
    for r in all_results:
        trips[(r["gob"], r.get("route_uid", ""), r["bus_start_ts"])].append(r)

    seg_deltas = defaultdict(list)   # (gob, sid_a, sid_b) → [delta_s, ...]
    seg_meta   = {}                  # 記錄路段 meta（seq、名稱）

    for (gob, _ruid, _bstart), events in trips.items():
        if len(events) < 2:
            continue
        # 去重：同 seq 只保留誤差最小的（避免 bus_start 同時追蹤多班殘留）
        by_seq = {}
        for ev in events:
            s = ev["seq"]
            if s not in by_seq or abs(ev["error_s"]) < abs(by_seq[s]["error_s"]):
                by_seq[s] = ev
        ordered = sorted(by_seq.values(), key=lambda x: x["seq"])

        for i in range(len(ordered) - 1):
            a, b = ordered[i], ordered[i + 1]
            gap = b["seq"] - a["seq"]
            if gap <= 0 or gap > MAX_SEQ_GAP:
                continue
            delta = b["error_s"] - a["error_s"]
            key = (gob, a["sid"], b["sid"])
            seg_deltas[key].append(delta)
            if key not in seg_meta:
                seg_meta[key] = {
                    "gob": gob,
                    "seq_a": a["seq"], "seq_b": b["seq"],
                    "name_a": a["name"], "name_b": b["name"],
                    "gap": gap,
                }

    return seg_deltas, seg_meta


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date",  default=datetime.now().strftime("%Y%m%d"))
    parser.add_argument("--dir",   default=os.path.join(os.path.dirname(__file__), "data"))
    parser.add_argument("--stops", default=None, help="bus_stops.json 路徑")
    parser.add_argument("--city",  default="taipei",
                        choices=["taipei", "newtaipei"],
                        help="城市（決定讀哪個 CSV）")
    parser.add_argument("--hours", type=float, default=3.0,
                        help="只分析最近 N 小時的資料（預設 3）")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--delta",   "-d", action="store_true", help="顯示路段 Δerror")
    args = parser.parse_args()

    # 支援新版（城市級）和舊版（路線級）CSV 命名
    city_csv  = os.path.join(args.dir, f"eta_snapshots_{args.city}_{args.date}.csv")
    # fallback: 舊版 205 only
    old_csv   = os.path.join(args.dir, f"eta_snapshots_{args.date}.csv")
    snap_csv  = city_csv if os.path.exists(city_csv) else old_csv

    if not os.path.exists(snap_csv):
        print(f"找不到 {snap_csv}")
        return

    # 時間窗口
    from datetime import timedelta
    since = datetime.now() - timedelta(hours=args.hours) if args.hours > 0 else None
    if since:
        print(f"（分析最近 {args.hours:.0f}h，since {since.strftime('%H:%M')}）")

    # 載入站名對照
    stops_json = args.stops or os.path.join(
        args.dir, f"{args.date[:8]}_1430_bus_stops.json"
    )
    stop_map = {}
    if os.path.exists(stops_json):
        stop_map = load_stops(stops_json)

    groups = load_snapshots(snap_csv, since=since)

    # 分析每個站
    all_results = []
    for (sid, gob), pts in groups.items():
        for r in analyze_stop(pts):
            r["sid"]  = sid
            r["gob"]  = gob
            info = stop_map.get(sid, {})
            r["name"] = info.get("name", f"?{sid}")
            r["seq"]  = info.get("seq", 0)
            all_results.append(r)

    # 彙總
    stop_errors = defaultdict(list)
    for r in all_results:
        stop_errors[(r["sid"], r["gob"])].append(r["error_s"])

    print(f"=== ETA 預測誤差分析 {args.date} ===")
    print(f"原始 ETA snapshot 組數：{len(groups)}")
    print(f"通過 filter 的 arrival event：{len(all_results)}")
    print()

    if not all_results:
        print("（尚無乾淨事件，繼續累積資料）")
        return

    print(f"{'方向':^4} {'Seq':^4} {'站名':<22} {'樣本':^5} {'平均誤差(s)':^12} {'最大':^8} {'判定':^6}")
    print("=" * 68)

    sorted_stops = sorted(
        stop_errors.items(),
        key=lambda x: (x[0][1], stop_map.get(x[0][0], {}).get("seq", 999))
    )

    cong_count = 0
    for (sid, gob), errs in sorted_stops:
        n    = len(errs)
        mean = sum(errs) / n
        mx   = max(errs)
        name = stop_map.get(sid, {}).get("name", f"?{sid}")
        seq  = stop_map.get(sid, {}).get("seq", 0)
        flag = "🔴" if mean > 60 else ("🟡" if mean > 20 else "✅")
        if mean > 60:
            cong_count += 1
        print(f"  {gob:^4}  {seq:^4}  {name:<22}  {n:^5}  {mean:^+12.0f}  {mx:^+8.0f}  {flag}")

        if args.verbose:
            for r in [x for x in all_results if x["sid"] == sid and x["gob"] == gob]:
                print(f"         bus_start={r['bus_start_ts'].strftime('%H:%M:%S')} "
                      f"ETA0={r['bus_start_eta']}s  "
                      f"predicted={r['predicted_ts'].strftime('%H:%M:%S')}  "
                      f"actual≈{r['actual_ts'].strftime('%H:%M:%S')}  "
                      f"error={r['error_s']:+.0f}s  "
                      f"polls={r['n_clean_polls']}")

    # 整體統計
    all_errs = [r["error_s"] for r in all_results]
    print()
    print(f"整體：n={len(all_errs)}")
    print(f"  mean={sum(all_errs)/len(all_errs):+.0f}s  "
          f"median={sorted(all_errs)[len(all_errs)//2]:+.0f}s")
    print(f"  max={max(all_errs):+.0f}s  min={min(all_errs):+.0f}s")
    print(f"  壅塞站（mean>60s）：{cong_count} 個")
    print(f"  誤差 >60s 的事件：{sum(1 for e in all_errs if e > 60)}")
    print(f"  誤差 >120s 的事件：{sum(1 for e in all_errs if e > 120)}")

    # ── 路段 Δerror ─────────────────────────────────────────────────────────
    if args.delta or args.verbose:
        seg_deltas, seg_meta = compute_segment_deltas(all_results)
        if not seg_deltas:
            print("\n（尚無跨站配對，繼續累積）")
        else:
            print()
            print("=== 路段壅塞增量 Δerror（路段實際旅行 − 預測旅行時間）===")
            print(f"{'方向':^4} {'路段 Seq':^10} {'路段名稱':<38} {'樣本':^5} {'平均Δ(s)':^10} {'判定':^6}")
            print("=" * 78)

            # 按 gob, seq_a 排序
            sorted_segs = sorted(
                seg_meta.items(),
                key=lambda x: (x[1]["gob"], x[1]["seq_a"])
            )

            seg_cong = 0
            for key, meta in sorted_segs:
                deltas = seg_deltas[key]
                n      = len(deltas)
                mean   = sum(deltas) / n
                mx     = max(deltas)
                label  = f"{meta['seq_a']}→{meta['seq_b']}"
                if meta["gap"] > 1:
                    label += f"(+{meta['gap']-1})"
                seg_name = f"{meta['name_a']} → {meta['name_b']}"
                flag = "🔴" if mean > 30 else ("🟡" if mean > 10 else ("✅" if mean >= -10 else "🟢"))
                if mean > 30:
                    seg_cong += 1
                print(f"  {meta['gob']:^4}  {label:^10}  {seg_name:<38}  {n:^5}  {mean:^+10.0f}  {flag}")
                if args.verbose:
                    for d in deltas:
                        print(f"             Δ={d:+.0f}s")

            print()
            print(f"  壅塞路段（meanΔ>30s）：{seg_cong} 個 / 共 {len(seg_meta)} 個路段")


if __name__ == "__main__":
    main()
