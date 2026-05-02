"""
crawler.py — 抓 PTT / Dcard 貼文
"""
import requests
import time
from datetime import datetime, timezone
from typing import Optional

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; FoodSafetyPoC/1.0)",
    "Cookie": "over18=1",
}


def fetch_ptt_board(board: str = "Food", pages: int = 3) -> list[dict]:
    """抓 PTT 看板最新文章列表"""
    posts = []
    url = f"https://www.ptt.cc/bbs/{board}/index.json"

    for _ in range(pages):
        try:
            r = requests.get(url, headers=HEADERS, timeout=10)
            r.raise_for_status()
            data = r.json()
            articles = data.get("articles", [])
            posts.extend(articles)

            # 往前翻頁
            prev_url = data.get("previous_page")
            if not prev_url:
                break
            url = f"https://www.ptt.cc{prev_url}.json"
            time.sleep(0.5)
        except Exception as e:
            print(f"[PTT] 抓取失敗: {e}")
            break

    return posts


def fetch_ptt_article(url_path: str) -> Optional[str]:
    """抓單篇 PTT 文章內文"""
    try:
        r = requests.get(
            f"https://www.ptt.cc{url_path}.json",
            headers=HEADERS,
            timeout=10
        )
        r.raise_for_status()
        data = r.json()
        return data.get("content", "")
    except Exception as e:
        print(f"[PTT] 文章抓取失敗 {url_path}: {e}")
        return None


def search_ptt(keyword: str, board: str = "Food") -> list[dict]:
    """搜尋 PTT 特定關鍵字（用 ptt.cx 第三方）"""
    try:
        r = requests.get(
            "https://ptt.cx/api/search",
            params={"q": keyword, "board": board},
            headers=HEADERS,
            timeout=10
        )
        r.raise_for_status()
        return r.json().get("hits", [])
    except Exception as e:
        print(f"[PTT Search] 失敗: {e}")
        return []


def search_dcard(keyword: str, limit: int = 30) -> list[dict]:
    """搜尋 Dcard 貼文"""
    try:
        r = requests.get(
            "https://www.dcard.tw/service/api/v2/search/posts",
            params={"query": keyword, "limit": limit},
            headers={**HEADERS, "Referer": "https://www.dcard.tw/"},
            timeout=10
        )
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"[Dcard] 搜尋失敗: {e}")
        return []


def fetch_dcard_forum(forum: str = "food", limit: int = 30) -> list[dict]:
    """抓 Dcard 版面最新文章"""
    try:
        r = requests.get(
            f"https://www.dcard.tw/service/api/v2/posts",
            params={"forum": forum, "limit": limit},
            headers={**HEADERS, "Referer": "https://www.dcard.tw/"},
            timeout=10
        )
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"[Dcard Forum] 抓取失敗: {e}")
        return []
