"""
KNARES Sentiment Fetcher
สคริปต์ดึงข่าว + sentiment จาก Alpha Vantage NEWS_SENTIMENT API
คำนวณ weighted sentiment score เฉพาะข่าวที่เกี่ยวข้องกับ USD/ทองคำ
แล้วเขียนผลลัพธ์เป็นไฟล์ JSON ให้ MT5 อ่านต่อ (คล้าย pattern ของ NewsConnector.mqh)

วิธีใช้:
  1. ใส่ ALPHAVANTAGE_API_KEY ในไฟล์ .env (โฟลเดอร์เดียวกับ webhook_bridge/.env หรือสร้างใหม่)
  2. รันด้วยมือ: python fetch_sentiment.py
  3. หรือตั้ง Windows Task Scheduler ให้รันทุก 1 ชั่วโมง (free tier จำกัด 25 req/วัน)

Rate limit: Alpha Vantage free tier = 25 requests/day
  ดังนั้นห้ามรันถี่กว่า 1 ครั้ง/ชั่วโมง (24 ครั้ง/วัน เผื่อไว้ 1 ครั้ง)
"""

import os
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv

SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR.parent / "webhook_bridge" / ".env")

API_KEY = os.getenv("ALPHAVANTAGE_API_KEY")
BASE_URL = "https://www.alphavantage.co/query"

# tickers ที่ถือว่าเกี่ยวข้องกับ XAUUSD โดยตรง
RELEVANT_TICKERS = {"FOREX:USD"}

# ไฟล์ output ที่ MT5 อ่านโดยตรง — เขียนเข้า MQL5/Files/ ของ terminal เลย (ไม่ต้อง copy มือ)
MT5_FILES_DIR = Path(
    r"C:\Users\Asus\AppData\Roaming\MetaQuotes\Terminal"
    r"\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files"
)
OUTPUT_FILE = MT5_FILES_DIR / "KNARES_SentimentCache.json"
# สำรองไว้อีกชุดในโฟลเดอร์โปรเจกต์ เผื่อดูผลย้อนหลัง/debug
BACKUP_FILE = SCRIPT_DIR.parent / "KNARES_SentimentCache.json"


def fetch_news_sentiment():
    if not API_KEY:
        print("ERROR: ไม่พบ ALPHAVANTAGE_API_KEY ใน .env", file=sys.stderr)
        sys.exit(1)

    params = {
        "function": "NEWS_SENTIMENT",
        "tickers": "FOREX:USD",
        "apikey": API_KEY,
    }
    resp = requests.get(BASE_URL, params=params, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    if "feed" not in data:
        # มักเป็น rate limit หรือ key ผิด — data จะมี "Information" หรือ "Note" แทน
        print(f"ERROR: API ไม่คืน feed กลับมา: {data}", file=sys.stderr)
        sys.exit(1)

    return data["feed"]


def compute_weighted_sentiment(feed):
    """
    คำนวณ weighted sentiment เฉพาะ ticker ที่เกี่ยวข้อง (FOREX:USD)
    weight = relevance_score ของ ticker นั้นในแต่ละข่าว
    """
    total_weight = 0.0
    weighted_sum = 0.0
    used_articles = []

    for article in feed:
        for t in article.get("ticker_sentiment", []):
            if t.get("ticker") not in RELEVANT_TICKERS:
                continue
            relevance = float(t.get("relevance_score", 0))
            score = float(t.get("ticker_sentiment_score", 0))
            if relevance <= 0:
                continue
            weighted_sum += score * relevance
            total_weight += relevance
            used_articles.append({
                "title": article.get("title"),
                "time_published": article.get("time_published"),
                "relevance_score": relevance,
                "ticker_sentiment_score": score,
                "ticker_sentiment_label": t.get("ticker_sentiment_label"),
            })
            break  # นับข่าวนี้ครั้งเดียวพอ (กันนับซ้ำถ้ามีหลาย ticker ตรงกัน)

    if total_weight == 0:
        return {
            "aggregate_score": 0.0,
            "aggregate_label": "NEUTRAL",
            "article_count": 0,
            "used_articles": [],
        }

    aggregate_score = weighted_sum / total_weight

    if aggregate_score <= -0.35:
        label = "BEARISH"
    elif aggregate_score <= -0.15:
        label = "SOMEWHAT_BEARISH"
    elif aggregate_score < 0.15:
        label = "NEUTRAL"
    elif aggregate_score < 0.35:
        label = "SOMEWHAT_BULLISH"
    else:
        label = "BULLISH"

    return {
        "aggregate_score": round(aggregate_score, 4),
        "aggregate_label": label,
        "article_count": len(used_articles),
        "used_articles": sorted(used_articles, key=lambda a: a["relevance_score"], reverse=True)[:10],
    }


def main():
    feed = fetch_news_sentiment()
    result = compute_weighted_sentiment(feed)
    result["generated_at_utc"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    result["source"] = "alphavantage_news_sentiment"

    for path in (OUTPUT_FILE, BACKUP_FILE):
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"Sentiment: {result['aggregate_label']} ({result['aggregate_score']}) "
          f"from {result['article_count']} relevant articles")
    print(f"Written to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
