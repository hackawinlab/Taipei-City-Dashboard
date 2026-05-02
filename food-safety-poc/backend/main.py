"""
main.py — 食安早期預警 PoC

用法：
  python main.py --mode keyword          # 關鍵字模式（不需 API）
  python main.py --mode llama            # Llama 模式
  python main.py --once                  # 單次執行
  python main.py --interval 15           # 每 15 分鐘執行一次
  python main.py --demo                  # 用寶林/饗饗假資料示範
"""
import argparse
import time
import os
from datetime import datetime, timezone, timedelta
from hashlib import md5

from crawler import search_ptt, search_dcard, fetch_dcard_forum
from classifier import classify_keyword, classify_llama, ClassifyResult
from detector import FoodSafetyDB, Post, Alert

# ── 設定 ──────────────────────────────────────────────────
SEARCH_KEYWORDS = [
    "食物中毒", "腸胃炎", "上吐下瀉", "吃壞肚子",
    "拉肚子", "嘔吐 餐廳",
]
PTT_BOARDS = ["Food", "Gossiping"]
DCARD_FORUMS = ["food", "talk"]

LLAMA_API_URL = os.getenv("LLAMA_API_URL", "https://api-free.twcc.ai/v1/chat/completions")
LLAMA_API_KEY = os.getenv("LLAMA_API_KEY", "")


def make_post_id(source: str, url: str) -> str:
    return md5(f"{source}:{url}".encode()).hexdigest()[:16]


def process_post(
    source: str,
    title: str,
    content: str,
    url: str,
    published_at: datetime,
    mode: str,
    db: FoodSafetyDB,
) -> list[Alert]:
    """處理單篇貼文，回傳觸發的 Alert（如果有）"""
    text = f"{title}\n{content}"

    # 分類
    if mode == "llama" and LLAMA_API_KEY:
        result: ClassifyResult = classify_llama(text, LLAMA_API_URL, LLAMA_API_KEY)
    else:
        result: ClassifyResult = classify_keyword(text)

    if not result.is_illness:
        return []

    post = Post(
        id=make_post_id(source, url),
        source=source,
        title=title,
        content=content[:1000],
        restaurant=result.restaurant,
        symptoms=result.symptoms,
        confidence=result.confidence,
        published_at=published_at,
        url=url,
    )

    is_new = db.save_post(post)
    if not is_new:
        return []  # 已處理過

    print(
        f"  ✅ [{source}] 新陽性貼文 | 餐廳: {result.restaurant or '未知'} "
        f"| 信心: {result.confidence:.0%} | {title[:40]}"
    )

    # 檢查群聚
    alerts = []
    if result.restaurant:
        alert = db.check_cluster(result.restaurant)
        if alert:
            alerts.append(alert)

    return alerts


def run_once(mode: str, db: FoodSafetyDB) -> list[Alert]:
    """單次抓取 + 分析"""
    all_alerts = []
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] 開始抓取...")

    # PTT 關鍵字搜尋
    for kw in SEARCH_KEYWORDS[:3]:  # PoC 只搜前幾個
        posts = search_ptt(kw, board="Food")
        for p in posts[:10]:
            alerts = process_post(
                source="ptt",
                title=p.get("title", ""),
                content=p.get("content", p.get("title", "")),
                url=p.get("url", ""),
                published_at=datetime.now(timezone.utc),
                mode=mode,
                db=db,
            )
            all_alerts.extend(alerts)

    # Dcard 版面最新文章
    for forum in DCARD_FORUMS:
        posts = fetch_dcard_forum(forum, limit=20)
        if not isinstance(posts, list):
            continue
        for p in posts:
            content = p.get("excerpt", "") or p.get("content", "")
            alerts = process_post(
                source="dcard",
                title=p.get("title", ""),
                content=content,
                url=f"https://www.dcard.tw/f/{forum}/p/{p.get('id','')}",
                published_at=datetime.fromisoformat(
                    p.get("createdAt", datetime.now(timezone.utc).isoformat())
                    .replace("Z", "+00:00")
                ),
                mode=mode,
                db=db,
            )
            all_alerts.extend(alerts)

    stats = db.get_stats()
    print(
        f"  📊 累計: {stats['total_posts']} 篇貼文, "
        f"{stats['posts_with_restaurant']} 篇有餐廳名, "
        f"{stats['total_alerts']} 次警報"
    )
    return all_alerts


def run_demo(db: FoodSafetyDB):
    """用寶林/饗饗假資料跑一次，展示系統可以偵測到"""
    print("\n🧪 Demo 模式 — 重播寶林茶室事件")

    demo_posts = [
        {
            "title": "寶林茶室吃完上吐下瀉",
            "content": "昨天在寶林茶室吃了粿條，今天一直上吐下瀉，肚子超痛，是食物中毒嗎？",
            "published_at": (datetime.now(timezone.utc) - timedelta(hours=10)).isoformat(),
        },
        {
            "title": "寶林茶室中毒",
            "content": "我昨天去寶林茶室吃炒粿條，吃完後腸胃炎，送急診了",
            "published_at": (datetime.now(timezone.utc) - timedelta(hours=6)).isoformat(),
        },
        {
            "title": "請問有人寶林茶室食物中毒嗎",
            "content": "我朋友昨天去寶林茶室用餐，今天嚴重嘔吐腹瀉，是不是食物中毒？",
            "published_at": (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(),
        },
    ]

    for p in demo_posts:
        alerts = process_post(
            source="ptt",
            title=p["title"],
            content=p["content"],
            url=f"https://ptt.cc/demo/{p['title']}",
            published_at=datetime.fromisoformat(p["published_at"]),
            mode="keyword",
            db=db,
        )
        if alerts:
            for alert in alerts:
                print(f"\n{alert}")
                print("📣 如果這是真實系統，此時衛生局尚未接獲通報（實際晚了 3-5 天）")


def main():
    parser = argparse.ArgumentParser(description="食安早期預警 PoC")
    parser.add_argument("--mode", choices=["keyword", "llama"], default="keyword")
    parser.add_argument("--once", action="store_true", help="單次執行後退出")
    parser.add_argument("--interval", type=int, default=15, help="輪詢間隔（分鐘）")
    parser.add_argument("--demo", action="store_true", help="用假資料示範")
    args = parser.parse_args()

    db = FoodSafetyDB()

    if args.demo:
        run_demo(db)
        return

    if args.once:
        alerts = run_once(args.mode, db)
        for alert in alerts:
            print(f"\n{alert}")
        return

    # 持續輪詢模式
    print(f"🚀 食安預警系統啟動 (模式: {args.mode}, 間隔: {args.interval}min)")
    while True:
        alerts = run_once(args.mode, db)
        for alert in alerts:
            print(f"\n{alert}")
            # TODO: 接 Telegram 通知

        print(f"  💤 等待 {args.interval} 分鐘後再次抓取...")
        time.sleep(args.interval * 60)


if __name__ == "__main__":
    main()
