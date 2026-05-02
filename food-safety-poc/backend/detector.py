"""
detector.py — 群聚偵測邏輯

規則：同一餐廳在 72 小時內出現 >= 3 篇陽性貼文 → 觸發 Alert
"""
import sqlite3
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass
from typing import Optional
from pathlib import Path

DB_PATH = Path(__file__).parent / "food_safety.db"
CLUSTER_WINDOW_HOURS = 72
CLUSTER_THRESHOLD = 3   # 同餐廳 N 篇以上觸發


@dataclass
class Post:
    id: str
    source: str           # "ptt" or "dcard"
    title: str
    content: str
    restaurant: Optional[str]
    symptoms: list[str]
    confidence: float
    published_at: datetime
    url: str


@dataclass
class Alert:
    restaurant: str
    post_count: int
    first_seen: datetime
    latest_seen: datetime
    posts: list[Post]

    def __str__(self):
        delta = self.latest_seen - self.first_seen
        return (
            f"🚨 食安警報！\n"
            f"餐廳：{self.restaurant}\n"
            f"72 小時內 {self.post_count} 篇貼文提到腸胃不適\n"
            f"首次出現：{self.first_seen.strftime('%Y-%m-%d %H:%M')}\n"
            f"最新一篇：{self.latest_seen.strftime('%Y-%m-%d %H:%M')}\n"
            f"時間跨度：{int(delta.total_seconds() / 3600)} 小時\n"
        )


class FoodSafetyDB:
    def __init__(self, db_path: Path = DB_PATH):
        self.conn = sqlite3.connect(db_path)
        self._init_db()

    def _init_db(self):
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS posts (
                id TEXT PRIMARY KEY,
                source TEXT,
                title TEXT,
                content TEXT,
                restaurant TEXT,
                symptoms TEXT,
                confidence REAL,
                published_at TEXT,
                url TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                restaurant TEXT,
                post_count INTEGER,
                first_seen TEXT,
                latest_seen TEXT,
                triggered_at TEXT DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_restaurant
                ON posts(restaurant, published_at);
        """)
        self.conn.commit()

    def save_post(self, post: Post) -> bool:
        """儲存貼文，回傳是否為新貼文"""
        try:
            self.conn.execute(
                """INSERT OR IGNORE INTO posts
                   (id, source, title, content, restaurant, symptoms,
                    confidence, published_at, url)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    post.id, post.source, post.title, post.content,
                    post.restaurant, ",".join(post.symptoms),
                    post.confidence,
                    post.published_at.isoformat(),
                    post.url,
                ),
            )
            self.conn.commit()
            return self.conn.total_changes > 0
        except Exception as e:
            print(f"[DB] save_post 失敗: {e}")
            return False

    def check_cluster(self, restaurant: str) -> Optional[Alert]:
        """檢查某餐廳是否觸發群聚條件"""
        if not restaurant:
            return None

        window_start = (
            datetime.now(timezone.utc) - timedelta(hours=CLUSTER_WINDOW_HOURS)
        ).isoformat()

        rows = self.conn.execute(
            """SELECT id, source, title, content, restaurant, symptoms,
                      confidence, published_at, url
               FROM posts
               WHERE restaurant = ?
                 AND published_at >= ?
                 AND confidence >= 0.3
               ORDER BY published_at ASC""",
            (restaurant, window_start),
        ).fetchall()

        if len(rows) < CLUSTER_THRESHOLD:
            return None

        posts = [
            Post(
                id=r[0], source=r[1], title=r[2], content=r[3],
                restaurant=r[4], symptoms=r[5].split(",") if r[5] else [],
                confidence=r[6],
                published_at=datetime.fromisoformat(r[7]),
                url=r[8],
            )
            for r in rows
        ]

        return Alert(
            restaurant=restaurant,
            post_count=len(posts),
            first_seen=posts[0].published_at,
            latest_seen=posts[-1].published_at,
            posts=posts,
        )

    def get_stats(self) -> dict:
        """取得目前統計"""
        total = self.conn.execute("SELECT COUNT(*) FROM posts").fetchone()[0]
        with_restaurant = self.conn.execute(
            "SELECT COUNT(*) FROM posts WHERE restaurant IS NOT NULL"
        ).fetchone()[0]
        alerts = self.conn.execute("SELECT COUNT(*) FROM alerts").fetchone()[0]
        return {
            "total_posts": total,
            "posts_with_restaurant": with_restaurant,
            "total_alerts": alerts,
        }
