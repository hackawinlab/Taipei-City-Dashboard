# /// script
# requires-python = ">=3.12"
# dependencies = ["pandas"]
# ///
"""依小時彙總 YouBike 剩餘車輛資料，並計算缺車相關指標。

讀取 data/youbike_Taipei 與 data/youbike_NewTaipei 下所有快照 CSV，
依 snapshot_at 的「小時」聚合，輸出三份結果到 data/youbike_hourly/：

1. youbike_hourly_by_station.csv   每小時 × 每站 的平均車輛、空位、電輔車數，
                                   以及 is_empty / is_low（缺車旗標）
2. youbike_hourly_summary.csv      每小時 × 城市 的總車輛、空位、平均使用率，
                                   以及 empty_ratio / low_ratio（缺車站比例）
3. youbike_shortage_top_stations.csv  缺車時數最多的前 50 站（兩個城市分別取）

缺車定義：
- empty: 平均可借車輛 < 1（該小時內幾乎沒有車）
- low:   平均可借車輛 ÷ 該站總車格 < 0.2（剩不到兩成容量）
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

DATA_DIR = Path(__file__).resolve().parent
SOURCES = {
    "Taipei": DATA_DIR / "youbike_Taipei",
    "NewTaipei": DATA_DIR / "youbike_NewTaipei",
}
OUT_DIR = DATA_DIR / "youbike_hourly"

EMPTY_THRESHOLD = 1.0  # 平均車輛 < 1 視為缺車（empty）
LOW_RATIO_THRESHOLD = 0.2  # 平均車輛 / 總車格 < 0.2 視為車量偏低（low）


def load_all() -> pd.DataFrame:
    frames: list[pd.DataFrame] = []
    for city, folder in SOURCES.items():
        files = sorted(folder.glob("*.csv"))
        if not files:
            print(f"[warn] {city} 沒有 CSV 檔案：{folder}")
            continue
        print(f"[info] {city}: 讀取 {len(files)} 個檔案")
        for f in files:
            df = pd.read_csv(f)
            frames.append(df)
    if not frames:
        raise SystemExit("沒有任何資料可處理")
    return pd.concat(frames, ignore_index=True)


def aggregate(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    df["snapshot_at"] = pd.to_datetime(df["snapshot_at"], utc=False)
    df["hour"] = df["snapshot_at"].dt.floor("h")

    by_station = (
        df.groupby(["hour", "city", "station_uid", "station_name", "lat", "lon"], as_index=False)
        .agg(
            avg_available_bikes=("available_bikes", "mean"),
            avg_available_docks=("available_docks", "mean"),
            avg_electric_bikes=("electric_bikes", "mean"),
            total_docks=("total_docks", "max"),
            samples=("available_bikes", "size"),
        )
        .sort_values(["hour", "city", "station_uid"])
    )
    by_station["fill_ratio"] = (
        by_station["avg_available_bikes"]
        / by_station["total_docks"].where(by_station["total_docks"] > 0)
    )
    by_station["is_empty"] = by_station["avg_available_bikes"] < EMPTY_THRESHOLD
    by_station["is_low"] = by_station["fill_ratio"] < LOW_RATIO_THRESHOLD
    by_station = by_station.round(
        {
            "avg_available_bikes": 2,
            "avg_available_docks": 2,
            "avg_electric_bikes": 2,
            "fill_ratio": 4,
        }
    )

    summary = (
        by_station.groupby(["hour", "city"], as_index=False)
        .agg(
            station_count=("station_uid", "nunique"),
            total_available_bikes=("avg_available_bikes", "sum"),
            total_available_docks=("avg_available_docks", "sum"),
            total_electric_bikes=("avg_electric_bikes", "sum"),
            total_docks=("total_docks", "sum"),
            mean_fill_ratio=("fill_ratio", "mean"),
            empty_stations=("is_empty", "sum"),
            low_stations=("is_low", "sum"),
        )
        .sort_values(["hour", "city"])
    )
    summary["empty_ratio"] = summary["empty_stations"] / summary["station_count"]
    summary["low_ratio"] = summary["low_stations"] / summary["station_count"]
    summary = summary.round(
        {
            "total_available_bikes": 2,
            "total_available_docks": 2,
            "total_electric_bikes": 2,
            "mean_fill_ratio": 4,
            "empty_ratio": 4,
            "low_ratio": 4,
        }
    )

    shortage_top = (
        by_station.groupby(
            ["city", "station_uid", "station_name", "lat", "lon"], as_index=False
        )
        .agg(
            hours_observed=("hour", "nunique"),
            empty_hours=("is_empty", "sum"),
            low_hours=("is_low", "sum"),
            avg_fill_ratio=("fill_ratio", "mean"),
        )
    )
    shortage_top["empty_hour_ratio"] = (
        shortage_top["empty_hours"] / shortage_top["hours_observed"]
    )
    shortage_top["low_hour_ratio"] = (
        shortage_top["low_hours"] / shortage_top["hours_observed"]
    )
    shortage_top = shortage_top.round(
        {"avg_fill_ratio": 4, "empty_hour_ratio": 4, "low_hour_ratio": 4}
    )
    shortage_top = (
        shortage_top.sort_values(
            ["city", "empty_hour_ratio", "low_hour_ratio"], ascending=[True, False, False]
        )
        .groupby("city", group_keys=False)
        .head(50)
    )

    return by_station, summary, shortage_top


def _strip_prefix(name: str) -> str:
    """移除站名重複的 YouBike2.0_ 前綴，方便畫圖。"""
    if not isinstance(name, str):
        return name
    for prefix in ("YouBike2.0_", "YouBike2_", "YouBike_"):
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


BURST_THRESHOLD = 5  # 單一 30 分鐘 snapshot 內 +5 視為調度卡車特徵


def compute_imbalance(df: pd.DataFrame, cities: list[str]) -> dict[str, dict]:
    """逐筆 snapshot 比對借出/歸還估計，輸出借還不對稱排名。

    snapshots 30 分鐘一次，無法看到區間內借出又歸還的活動，因此這裡得到的是「下界」估計：
    - est_borrow = Σ |negative deltas|（區間 net 下降量）
    - est_return = Σ positive deltas（區間 net 上升量；含調度卡車補車）
    - imbalance = est_return - est_borrow（最負代表「流出 ≫ 歸還」，調度路線的固定客戶）

    補車依賴度（dispatch_dependency）：
    - 把 est_return 拆 burst (delta >= BURST_THRESHOLD) vs steady。
    - dispatch_dependency = est_return_burst / max(est_return, 1)
    - 越接近 1：站點靠卡車補車撐住、撤補車就崩；越接近 0：自循環健康。

    人均淨流出（imbalance_per_dock）：
    - imbalance / total_docks
    - 解開「絕對流出」對大站的 docks-size 偏向；可讓中型站（30–80 docks）公平上榜，
      與 Block 2 長期缺車排行（小站 22–60 docks）有交集才能講「物種對照」框架。

    回傳兩個排行：
    - "absolute"：依 |imbalance| 由大到小（保留原本「車一去不返」榜單）
    - "per_dock"：依 imbalance_per_dock 由負到正（人均流出大）
    """
    flow = df.copy().sort_values(["station_uid", "snapshot_at"])
    flow["prev_bikes"] = flow.groupby("station_uid")["available_bikes"].shift(1)
    flow["delta"] = flow["available_bikes"] - flow["prev_bikes"]
    flow = flow.dropna(subset=["delta"])
    flow["est_borrow"] = (-flow["delta"]).clip(lower=0)
    flow["est_return"] = flow["delta"].clip(lower=0)
    flow["est_return_burst"] = flow["est_return"].where(
        flow["est_return"] >= BURST_THRESHOLD, 0
    )
    flow["est_return_steady"] = flow["est_return"].where(
        flow["est_return"] < BURST_THRESHOLD, 0
    )

    imbalance_df = (
        flow.groupby(["city", "station_uid", "station_name"], as_index=False)
        .agg(
            est_borrow=("est_borrow", "sum"),
            est_return=("est_return", "sum"),
            est_return_burst=("est_return_burst", "sum"),
            est_return_steady=("est_return_steady", "sum"),
            samples=("delta", "size"),
        )
    )
    imbalance_df["imbalance"] = imbalance_df["est_return"] - imbalance_df["est_borrow"]
    imbalance_df["dispatch_dependency"] = (
        imbalance_df["est_return_burst"] / imbalance_df["est_return"].clip(lower=1)
    ).round(3)
    docks_lookup = (
        df.drop_duplicates("station_uid")
        .set_index("station_uid")["total_docks"]
        .to_dict()
    )
    imbalance_df["total_docks"] = (
        imbalance_df["station_uid"].map(docks_lookup).fillna(0).astype(int)
    )
    imbalance_df["imbalance_per_dock"] = (
        imbalance_df["imbalance"]
        / imbalance_df["total_docks"].clip(lower=1)
    ).round(4)

    def serialize_row(r) -> dict:
        return {
            "station_name": _strip_prefix(r.station_name),
            "city": r.city,
            "est_borrow": int(round(r.est_borrow)),
            "est_return": int(round(r.est_return)),
            "est_return_burst": int(round(r.est_return_burst)),
            "est_return_steady": int(round(r.est_return_steady)),
            "imbalance": int(round(r.imbalance)),
            "imbalance_per_dock": float(r.imbalance_per_dock),
            "dispatch_dependency": float(r.dispatch_dependency),
            "total_docks": int(r.total_docks),
        }

    out: dict[str, dict] = {}
    for city in cities:
        view = (
            imbalance_df
            if city == "All"
            else imbalance_df[imbalance_df["city"] == city]
        )
        # 絕對流出排行：大站為主（保留原 Block 4）
        absolute = view.sort_values("imbalance", ascending=True).head(15)
        # 人均流出排行：擺脫 docks 大小、可讓中小站擠上來（與 Block 2 交集才有對照故事）
        # 過濾掉 docks < 10 的極小站避免比例被放大成噪訊
        per_dock = (
            view[view["total_docks"] >= 10]
            .sort_values("imbalance_per_dock", ascending=True)
            .head(15)
        )
        out[city] = {
            "absolute": [
                serialize_row(r) for r in absolute.itertuples(index=False)
            ],
            "per_dock": [
                serialize_row(r) for r in per_dock.itertuples(index=False)
            ],
        }
    return out


def write_frontend_json(
    by_station: pd.DataFrame,
    summary: pd.DataFrame,
    imbalance: dict[str, list[dict]],
    path: Path,
    top_n: int = 30,
) -> None:
    """輸出前端 dashboard 用的 JSON。

    結構：
    {
      "hours": ["2026-05-01 02:00", ...],
      "cities": ["Taipei", "NewTaipei", "All"],
      "summary": { "<hour>": { "<city>": {empty_ratio, low_ratio, ...} } },
      "rankings": {
        "<hour>": {
          "<city>": [
            {station_name, shortage_ratio, available_bikes, total_docks, ...}
          ]
        }
      }
    }
    """
    df = by_station.copy()
    df["shortage_ratio"] = (1.0 - df["fill_ratio"]).clip(lower=0.0).round(4)
    df["hour_label"] = pd.to_datetime(df["hour"]).dt.strftime("%Y-%m-%d %H:%M")

    hours = sorted(df["hour_label"].unique().tolist())
    cities = ["All", "Taipei", "NewTaipei"]

    rankings: dict[str, dict[str, list[dict]]] = {}
    for hour in hours:
        hour_df = df[df["hour_label"] == hour]
        rankings[hour] = {}
        for city in cities:
            view = hour_df if city == "All" else hour_df[hour_df["city"] == city]
            ranked = (
                view[view["total_docks"] > 0]
                .sort_values(
                    ["shortage_ratio", "avg_available_bikes"], ascending=[False, True]
                )
                .head(top_n)
            )
            rankings[hour][city] = [
                {
                    "station_uid": r.station_uid,
                    "station_name": r.station_name,
                    "city": r.city,
                    "lat": float(r.lat),
                    "lon": float(r.lon),
                    "shortage_ratio": float(r.shortage_ratio),
                    "fill_ratio": float(r.fill_ratio),
                    "avg_available_bikes": float(r.avg_available_bikes),
                    "total_docks": int(r.total_docks),
                    "is_empty": bool(r.is_empty),
                    "is_low": bool(r.is_low),
                }
                for r in ranked.itertuples(index=False)
            ]

    summary_out: dict[str, dict[str, dict]] = {}
    for r in summary.itertuples(index=False):
        hour_label = pd.to_datetime(r.hour).strftime("%Y-%m-%d %H:%M")
        summary_out.setdefault(hour_label, {})[r.city] = {
            "station_count": int(r.station_count),
            "empty_stations": int(r.empty_stations),
            "low_stations": int(r.low_stations),
            "empty_ratio": float(r.empty_ratio),
            "low_ratio": float(r.low_ratio),
            "mean_fill_ratio": float(r.mean_fill_ratio),
        }

    # === 為多 block dashboard 補充資料 ===

    # 1. 慢性缺車排行（依 empty_hour_ratio 全時段排名，取前 25 站）
    persistence = (
        df.groupby(["city", "station_uid", "station_name"], as_index=False)
        .agg(
            hours_observed=("hour", "nunique"),
            empty_hours=("is_empty", "sum"),
            low_hours=("is_low", "sum"),
            avg_fill_ratio=("fill_ratio", "mean"),
            total_docks=("total_docks", "max"),
        )
    )
    persistence["empty_hour_ratio"] = (
        persistence["empty_hours"] / persistence["hours_observed"]
    ).round(4)
    persistence["low_hour_ratio"] = (
        persistence["low_hours"] / persistence["hours_observed"]
    ).round(4)
    persistence["avg_fill_ratio"] = persistence["avg_fill_ratio"].round(4)

    bar_persistence: dict[str, list[dict]] = {}
    for city in cities:
        view = (
            persistence
            if city == "All"
            else persistence[persistence["city"] == city]
        )
        ranked = view.sort_values(
            ["empty_hour_ratio", "low_hour_ratio", "total_docks"],
            ascending=[False, False, False],
        ).head(25)
        bar_persistence[city] = [
            {
                "station_name": _strip_prefix(r.station_name),
                "city": r.city,
                "empty_hours": int(r.empty_hours),
                "low_hours": int(r.low_hours),
                "hours_observed": int(r.hours_observed),
                "empty_hour_ratio": float(r.empty_hour_ratio),
                "low_hour_ratio": float(r.low_hour_ratio),
                "avg_fill_ratio": float(r.avg_fill_ratio),
                "total_docks": int(r.total_docks),
            }
            for r in ranked.itertuples(index=False)
        ]

    # 2. 站 × 小時 熱力圖：取「全日填充率波動最大」的 25 站。
    #    舊邏輯：max − min fill_ratio。問題：偏向小站（22 格站從滿到空 = 100%→0%）、
    #    被選中的站集中在容量小、波動百分比相對放大的觀光站，與 Block 2/4 都零重疊、
    #    講「車流方向」的故事失準。
    #    新邏輯：(a) 先過濾 total_docks >= 30（剔除小站噪訊），
    #           (b) 排序改用 std of fill_ratio（穩健、不受單一極端點主導）。
    HEATMAP_MIN_DOCKS = 30
    fill_stats = (
        df.groupby("station_uid")["fill_ratio"]
        .agg(["std", "min", "max"])
        .fillna(0.0)
    )
    fill_stats["range"] = fill_stats["max"] - fill_stats["min"]
    fill_stats["station_uid"] = fill_stats.index
    fill_stats_meta = (
        df.drop_duplicates("station_uid")[["station_uid", "city", "total_docks"]]
        .set_index("station_uid")
    )
    fill_stats = fill_stats.join(fill_stats_meta, how="left")
    fill_stats = fill_stats[fill_stats["total_docks"] >= HEATMAP_MIN_DOCKS]

    heatmap: dict[str, dict] = {}
    for city in cities:
        view = (
            fill_stats
            if city == "All"
            else fill_stats[fill_stats["city"] == city]
        )
        # 依 fill_ratio 標準差排序（早高晚低 / 早低晚高的站 std 最大，整天平坦的站 std 接近 0）
        top_stations = (
            view.sort_values("std", ascending=False)
            .head(25)
            .index.tolist()
        )
        sub = df[df["station_uid"].isin(top_stations)].copy()
        sub["hour_label"] = pd.to_datetime(sub["hour"]).dt.strftime("%H:%M")
        # 每站 × 每小時 取平均 fill_ratio，並轉成百分比 (0..100)
        pivot = (
            sub.pivot_table(
                index="station_uid",
                columns="hour_label",
                values="fill_ratio",
                aggfunc="mean",
            )
            .reindex(index=top_stations)
            .sort_index(axis=1)
        )
        # 維持站名標籤順序（依排行）
        name_lookup = (
            df.drop_duplicates("station_uid")
            .set_index("station_uid")["station_name"]
            .to_dict()
        )
        rows = []
        for uid, row in pivot.iterrows():
            rows.append(
                {
                    "name": _strip_prefix(name_lookup.get(uid, uid)),
                    "data": [
                        {
                            "x": col,
                            "y": (
                                round(float(row[col]) * 100, 1)
                                if pd.notna(row[col])
                                else None
                            ),
                        }
                        for col in pivot.columns
                    ],
                }
            )
        heatmap[city] = {
            "categories": pivot.columns.tolist(),
            "series": rows,
        }

    # 3. 時間序列：每小時 empty_ratio (%) 與 low_ratio (%)，每個城市一條線
    timeline_empty: list[dict] = []
    timeline_low: list[dict] = []
    for city in ["Taipei", "NewTaipei"]:
        empty_pts = []
        low_pts = []
        for hour, sub in summary[summary["city"] == city].iterrows():
            iso = pd.to_datetime(sub["hour"]).isoformat()
            empty_pts.append({"x": iso, "y": round(float(sub["empty_ratio"]) * 100, 2)})
            low_pts.append({"x": iso, "y": round(float(sub["low_ratio"]) * 100, 2)})
        timeline_empty.append({"name": city, "data": empty_pts})
        timeline_low.append({"name": city, "data": low_pts})

    # 4. 散布資料：每小時每站的 lat/lon + fill_ratio + total_docks（給 ScatterChart 用）
    df_geo = by_station.copy()
    df_geo["hour_label"] = pd.to_datetime(df_geo["hour"]).dt.strftime("%Y-%m-%d %H:%M")
    scatter: dict[str, dict[str, list[dict]]] = {}
    for hour in hours:
        scatter[hour] = {}
        sub_hour = df_geo[df_geo["hour_label"] == hour]
        for city in cities:
            view = sub_hour if city == "All" else sub_hour[sub_hour["city"] == city]
            scatter[hour][city] = [
                {
                    "name": _strip_prefix(r.station_name),
                    "city": r.city,
                    "lat": float(r.lat),
                    "lon": float(r.lon),
                    "fill_ratio": float(r.fill_ratio) if pd.notna(r.fill_ratio) else 0.0,
                    "total_docks": int(r.total_docks),
                    "available_bikes": float(r.avg_available_bikes),
                }
                for r in view.itertuples(index=False)
            ]


    payload = {
        "generated_at": pd.Timestamp.now().isoformat(timespec="seconds"),
        "hours": hours,
        "cities": cities,
        "top_n": top_n,
        "summary": summary_out,
        "rankings": rankings,
        "bar_persistence": bar_persistence,
        "heatmap": heatmap,
        "timeline_empty": timeline_empty,
        "timeline_low": timeline_low,
        "scatter": scatter,
        "imbalance": imbalance,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    df = load_all()
    print(f"[info] 共 {len(df):,} 筆原始紀錄")
    by_station, summary, shortage_top = aggregate(df)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    station_path = OUT_DIR / "youbike_hourly_by_station.csv"
    summary_path = OUT_DIR / "youbike_hourly_summary.csv"
    shortage_path = OUT_DIR / "youbike_shortage_top_stations.csv"
    by_station.to_csv(station_path, index=False)
    summary.to_csv(summary_path, index=False)
    shortage_top.to_csv(shortage_path, index=False)
    print(f"[done] 寫出每小時每站：{station_path} ({len(by_station):,} 列)")
    print(f"[done] 寫出每小時彙總：{summary_path} ({len(summary):,} 列)")
    print(f"[done] 寫出缺車站排行：{shortage_path} ({len(shortage_top):,} 列)")

    # 輸出給前端 dashboard 使用的 JSON：每小時 × 城市 的缺車排行（前 30 站）
    fe_data_dir = (
        DATA_DIR.parent
        / "Taipei-City-Dashboard-FE"
        / "public"
        / "data"
    )
    fe_data_dir.mkdir(parents=True, exist_ok=True)
    fe_json_path = fe_data_dir / "youbike_hourly_shortage.json"
    imbalance = compute_imbalance(df, ["All", "Taipei", "NewTaipei"])
    write_frontend_json(by_station, summary, imbalance, fe_json_path)
    print(f"[done] 寫出前端 JSON：{fe_json_path}")

    # 列出缺車尖峰時段（兩城市合計 empty_ratio 最高的前 5 小時）
    peak = (
        summary.assign(empty_count=summary["empty_stations"])
        .groupby("hour", as_index=False)
        .agg(
            total_stations=("station_count", "sum"),
            total_empty=("empty_stations", "sum"),
            total_low=("low_stations", "sum"),
        )
    )
    peak["empty_ratio"] = (peak["total_empty"] / peak["total_stations"]).round(4)
    peak["low_ratio"] = (peak["total_low"] / peak["total_stations"]).round(4)
    peak = peak.sort_values("empty_ratio", ascending=False).head(5)
    print("\n[summary] 缺車尖峰時段（兩城市合併）：")
    print(peak.to_string(index=False))


if __name__ == "__main__":
    main()
