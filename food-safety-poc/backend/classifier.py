"""
classifier.py — 偵測貼文是否描述腸胃不適 + 抽取餐廳名稱

兩種模式：
  - keyword: 快速關鍵字比對（PoC 用）
  - llama:   呼叫 TWCC Llama API（正式用）
"""
import re
import json
import requests
from dataclasses import dataclass
from typing import Optional

# ── 腸胃不適關鍵字 ────────────────────────────────────────
GI_KEYWORDS = [
    "食物中毒", "腸胃炎", "上吐下瀉", "拉肚子", "腹瀉",
    "嘔吐", "噁心", "腸胃不適", "腸胃不舒服", "吃壞肚子",
    "拉到虛脫", "肚子痛", "腹痛", "跑廁所", "拉了一整晚",
    "嘔到", "吐到", "中毒", "食安",
]

# 餐廳/用餐相關上下文關鍵字（避免誤判非用餐場合）
EATING_CONTEXT = [
    "吃", "餐廳", "用餐", "店", "料理", "食堂", "便當",
    "外送", "foodpanda", "ubereats", "點餐", "訂餐",
]


@dataclass
class ClassifyResult:
    is_illness: bool
    confidence: float        # 0.0 ~ 1.0
    restaurant: Optional[str]
    symptoms: list[str]
    method: str              # "keyword" or "llama"


def classify_keyword(text: str) -> ClassifyResult:
    """關鍵字模式（無需 API，PoC 用）"""
    text_lower = text.lower()

    # 找到的症狀關鍵字
    found_symptoms = [kw for kw in GI_KEYWORDS if kw in text]
    has_eating_context = any(kw in text for kw in EATING_CONTEXT)

    is_illness = len(found_symptoms) >= 1 and has_eating_context
    confidence = min(0.9, len(found_symptoms) * 0.3) if is_illness else 0.0

    # 簡單餐廳名稱抽取（找「XXX 店/餐廳/食堂」模式）
    restaurant = _extract_restaurant_keyword(text)

    return ClassifyResult(
        is_illness=is_illness,
        confidence=confidence,
        restaurant=restaurant,
        symptoms=found_symptoms,
        method="keyword",
    )


def classify_llama(text: str, api_url: str, api_key: str) -> ClassifyResult:
    """Llama 模式（呼叫 TWCC FFM API）"""
    system_prompt = """你是一個食品安全監測助手。
請分析以下貼文，判斷是否描述了「在某餐廳或特定地點用餐後出現腸胃不適症狀」。

回傳嚴格的 JSON 格式，不要有其他文字：
{
  "is_illness": true 或 false,
  "confidence": 0.0 到 1.0 的數字,
  "restaurant": "餐廳名稱或 null",
  "symptoms": ["症狀1", "症狀2"]
}

判斷標準：
- is_illness=true：文章明確提到用餐後出現腸胃症狀（腹瀉、嘔吐、食物中毒等）
- restaurant：盡量抽取具體餐廳名稱，抽不到就填 null
- confidence：你對判斷的信心程度"""

    try:
        r = requests.post(
            api_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "llama3.3-ffm-70b-16k-chat",
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"貼文內容：\n{text[:2000]}"},
                ],
                "temperature": 0.1,
                "max_tokens": 200,
            },
            timeout=30,
        )
        r.raise_for_status()
        content = r.json()["choices"][0]["message"]["content"]

        # 解析 JSON
        result = json.loads(content)
        return ClassifyResult(
            is_illness=result.get("is_illness", False),
            confidence=float(result.get("confidence", 0.0)),
            restaurant=result.get("restaurant"),
            symptoms=result.get("symptoms", []),
            method="llama",
        )
    except Exception as e:
        print(f"[Llama] 分類失敗: {e}，fallback 到 keyword")
        return classify_keyword(text)


# ── helpers ──────────────────────────────────────────────
def _extract_restaurant_keyword(text: str) -> Optional[str]:
    """從文章抽取餐廳名稱（關鍵字模式的簡單版）"""
    patterns = [
        r"([^\s，。！？\n]{2,10}(?:餐廳|餐館|食堂|小吃|火鍋|燒肉|壽司|拉麵|便當|麵店|飯店|牛排|咖啡廳|咖啡店))",
        r"(?:在|去|到|吃了?)\s*([^\s，。！？\n]{2,15})(?:\s*吃|用餐|點餐)",
        r"([^\s，。！？\n]{2,15})\s*(?:的|裡|那家|這家)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(1).strip()
    return None
