"""Bhromon Newspaper Hub & Ad-Free News Aggregation Service.

Provides:
1. Live RSS/Atom news headlines from top Bangladesh and global newspapers.
2. Newspaper Directory with categorized entries and favorites support.
3. "Same story, different papers" smart topic clustering across multiple publications.
4. Ad-Free Clean Reader: strips ads, banners, trackers, scripts, popups, and returns
   clean distraction-free typography ready for readability & TTS audio read-out.
5. Persistent thread-safe SQLite caching (WAL mode) for minimal bandwidth and offline readiness.
"""

import gzip
import hashlib
import html
import logging
import os
import re
import sqlite3
import threading
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

logger = logging.getLogger("bhromon-news")

META_ROOT = Path(os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
NEWS_DB_PATH = Path(os.getenv("NEWS_DB_PATH", str(META_ROOT / "bhromon_news.db")))

router = APIRouter()


def _now_ms() -> int:
    return int(time.time() * 1000)


# ---------------------------------------------------------------------------
# Newspaper Directory Catalog
# ---------------------------------------------------------------------------

NEWSPAPER_CATALOG: List[Dict[str, Any]] = [
    # --- Bangla Dailies ---
    {
        "id": "prothom_alo",
        "name": "Prothom Alo",
        "nameBn": "প্রথম আলো",
        "domain": "prothomalo.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.prothomalo.com/feed",
        "websiteUrl": "https://www.prothomalo.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "kaler_kantho",
        "name": "Kaler Kantho",
        "nameBn": "কালের কণ্ঠ",
        "domain": "kalerkantho.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.kalerkantho.com/rss.xml",
        "websiteUrl": "https://www.kalerkantho.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "samakal",
        "name": "Samakal",
        "nameBn": "সমকাল",
        "domain": "samakal.com",
        "category": "bangla_dailies",
        "rssUrl": "https://samakal.com/rss.xml",
        "websiteUrl": "https://samakal.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "jugantor",
        "name": "Jugantor",
        "nameBn": "যুগান্তর",
        "domain": "jugantor.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.jugantor.com/feed/rss.xml",
        "websiteUrl": "https://www.jugantor.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "ittefaq",
        "name": "The Daily Ittefaq",
        "nameBn": "দৈনিক ইত্তেফাক",
        "domain": "ittefaq.com.bd",
        "category": "bangla_dailies",
        "rssUrl": "https://www.ittefaq.com.bd/rss.xml",
        "websiteUrl": "https://www.ittefaq.com.bd",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "manab_zamin",
        "name": "Manab Zamin",
        "nameBn": "মানবজমিন",
        "domain": "mzamin.com",
        "category": "bangla_dailies",
        "rssUrl": "https://mzamin.com/rss.xml",
        "websiteUrl": "https://mzamin.com",
        "language": "bn",
        "isPopular": False,
    },
    {
        "id": "daily_inqilab",
        "name": "Daily Inqilab",
        "nameBn": "দৈনিক ইনকিলাব",
        "domain": "dailyinqilab.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.dailyinqilab.com/rss.xml",
        "websiteUrl": "https://www.dailyinqilab.com",
        "language": "bn",
        "isPopular": False,
    },
    {
        "id": "bhorer_kagoj",
        "name": "Bhorer Kagoj",
        "nameBn": "ভোরের কাগজ",
        "domain": "bhorerkagoj.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.bhorerkagoj.com/feed",
        "websiteUrl": "https://www.bhorerkagoj.com",
        "language": "bn",
        "isPopular": False,
    },
    {
        "id": "naya_diganta",
        "name": "Daily Naya Diganta",
        "nameBn": "নয়া দিগন্ত",
        "domain": "dailynayadiganta.com",
        "category": "bangla_dailies",
        "rssUrl": "https://www.dailynayadiganta.com/rss.xml",
        "websiteUrl": "https://www.dailynayadiganta.com",
        "language": "bn",
        "isPopular": False,
    },

    # --- English Dailies ---
    {
        "id": "daily_star",
        "name": "The Daily Star",
        "nameBn": "দ্য ডেইলি স্টার",
        "domain": "thedailystar.net",
        "category": "english_dailies",
        "rssUrl": "https://www.thedailystar.net/frontpage/rss.xml",
        "websiteUrl": "https://www.thedailystar.net",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "dhaka_tribune",
        "name": "Dhaka Tribune",
        "nameBn": "ঢাকা ট্রিবিউন",
        "domain": "dhakatribune.com",
        "category": "english_dailies",
        "rssUrl": "https://www.dhakatribune.com/feed",
        "websiteUrl": "https://www.dhakatribune.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "tbs",
        "name": "The Business Standard",
        "nameBn": "দ্য বিজনেস স্ট্যান্ডার্ড",
        "domain": "tbsnews.net",
        "category": "english_dailies",
        "rssUrl": "https://www.tbsnews.net/rss.xml",
        "websiteUrl": "https://www.tbsnews.net",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "new_age",
        "name": "New Age",
        "nameBn": "নিউ এজ",
        "domain": "newagebd.net",
        "category": "english_dailies",
        "rssUrl": "https://www.newagebd.net/rss.xml",
        "websiteUrl": "https://www.newagebd.net",
        "language": "en",
        "isPopular": False,
    },
    {
        "id": "financial_express",
        "name": "The Financial Express",
        "nameBn": "দ্য ফিনান্সিয়াল এক্সপ্রেস",
        "domain": "thefinancialexpress.com.bd",
        "category": "english_dailies",
        "rssUrl": "https://today.thefinancialexpress.com.bd/rss.xml",
        "websiteUrl": "https://today.thefinancialexpress.com.bd",
        "language": "en",
        "isPopular": False,
    },
    {
        "id": "daily_sun",
        "name": "Daily Sun",
        "nameBn": "ডেইলি সান",
        "domain": "daily-sun.com",
        "category": "english_dailies",
        "rssUrl": "https://www.daily-sun.com/rss.xml",
        "websiteUrl": "https://www.daily-sun.com",
        "language": "en",
        "isPopular": False,
    },

    # --- Online Portals ---
    {
        "id": "bdnews24",
        "name": "bdnews24.com",
        "nameBn": "বিডিনিউজ টোয়েন্টিফোর",
        "domain": "bdnews24.com",
        "category": "online_portals",
        "rssUrl": "https://bangla.bdnews24.com/?widgetName=rssfeed&widgetId=1151&getXmlFeed=true",
        "websiteUrl": "https://bdnews24.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "bangla_tribune",
        "name": "Bangla Tribune",
        "nameBn": "বাংলা ট্রিবিউন",
        "domain": "banglatribune.com",
        "category": "online_portals",
        "rssUrl": "https://www.banglatribune.com/feed/",
        "websiteUrl": "https://www.banglatribune.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "jago_news",
        "name": "Jago News 24",
        "nameBn": "জাগো নিউজ ২৪",
        "domain": "jagonews24.com",
        "category": "online_portals",
        "rssUrl": "https://www.jagonews24.com/rss/rss.xml",
        "websiteUrl": "https://www.jagonews24.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "dhaka_post",
        "name": "Dhaka Post",
        "nameBn": "ঢাকা পোস্ট",
        "domain": "dhakapost.com",
        "category": "online_portals",
        "rssUrl": "https://www.dhakapost.com/rss",
        "websiteUrl": "https://www.dhakapost.com",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "risingbd",
        "name": "RisingBD",
        "nameBn": "রাইজিংবিডি",
        "domain": "risingbd.com",
        "category": "online_portals",
        "rssUrl": "https://www.risingbd.com/rss.xml",
        "websiteUrl": "https://www.risingbd.com",
        "language": "bn",
        "isPopular": False,
    },

    # --- World & Tech ---
    {
        "id": "bbc_bangla",
        "name": "BBC News Bangla",
        "nameBn": "বিবিসি বাংলা",
        "domain": "bbc.com/bengali",
        "category": "world_tech",
        "rssUrl": "https://feeds.bbci.co.uk/bengali/rss.xml",
        "websiteUrl": "https://www.bbc.com/bengali",
        "language": "bn",
        "isPopular": True,
    },
    {
        "id": "bbc_news",
        "name": "BBC News",
        "nameBn": "বিবিসি নিউজ",
        "domain": "bbc.com",
        "category": "world_tech",
        "rssUrl": "https://feeds.bbci.co.uk/news/world/rss.xml",
        "websiteUrl": "https://www.bbc.com/news",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "al_jazeera",
        "name": "Al Jazeera",
        "nameBn": "আল জাজিরা",
        "domain": "aljazeera.com",
        "category": "world_tech",
        "rssUrl": "https://www.aljazeera.com/xml/rss/all.xml",
        "websiteUrl": "https://www.aljazeera.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "cnn",
        "name": "CNN",
        "nameBn": "সিএনএন",
        "domain": "cnn.com",
        "category": "world_tech",
        "rssUrl": "http://rss.cnn.com/rss/edition.rss",
        "websiteUrl": "https://edition.cnn.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "the_guardian",
        "name": "The Guardian",
        "nameBn": "দ্য গার্ডিয়ান",
        "domain": "theguardian.com",
        "category": "world_tech",
        "rssUrl": "https://www.theguardian.com/world/rss",
        "websiteUrl": "https://www.theguardian.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "dw_bangla",
        "name": "Deutsche Welle (DW)",
        "nameBn": "ডয়চে ভেলে বাংলা",
        "domain": "dw.com/bn",
        "category": "world_tech",
        "rssUrl": "https://rss.dw.com/rdf/rss-ben-all",
        "websiteUrl": "https://www.dw.com/bn",
        "language": "bn",
        "isPopular": False,
    },
    {
        "id": "the_verge",
        "name": "The Verge",
        "nameBn": "দ্য ভার্জ",
        "domain": "theverge.com",
        "category": "world_tech",
        "rssUrl": "https://www.theverge.com/rss/index.xml",
        "websiteUrl": "https://www.theverge.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "techcrunch",
        "name": "TechCrunch",
        "nameBn": "টেকক্রাঞ্চ",
        "domain": "techcrunch.com",
        "category": "world_tech",
        "rssUrl": "https://techcrunch.com/feed/",
        "websiteUrl": "https://techcrunch.com",
        "language": "en",
        "isPopular": True,
    },

    # --- Sports ---
    {
        "id": "cricinfo",
        "name": "ESPNcricinfo",
        "nameBn": "ইএসপিএন ক্রিকইনফো",
        "domain": "espncricinfo.com",
        "category": "sports",
        "rssUrl": "https://www.espncricinfo.com/rss/content/story/feeds/0.xml",
        "websiteUrl": "https://www.espncricinfo.com",
        "language": "en",
        "isPopular": True,
    },
    {
        "id": "prothom_alo_sports",
        "name": "Prothom Alo Sports",
        "nameBn": "খেলা - প্রথম আলো",
        "domain": "prothomalo.com/sports",
        "category": "sports",
        "rssUrl": "https://www.prothomalo.com/sports/feed",
        "websiteUrl": "https://www.prothomalo.com/sports",
        "language": "bn",
        "isPopular": True,
    },
]

# Quick map by id
NEWSPAPER_MAP = {p["id"]: p for p in NEWSPAPER_CATALOG}


# ---------------------------------------------------------------------------
# Database Storage (SQLite WAL Mode)
# ---------------------------------------------------------------------------

class NewsDatabase:
    """Thread-safe SQLite storage for news headlines and ad-free parsed articles."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = str(db_path)
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self._local = threading.local()
        self._init_schema()

    def _get_conn(self) -> sqlite3.Connection:
        if not hasattr(self._local, "conn") or self._local.conn is None:
            conn = sqlite3.connect(self.db_path, timeout=30.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            self._local.conn = conn
        return self._local.conn

    def _init_schema(self) -> None:
        conn = self._get_conn()
        with conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS headlines (
                    id TEXT PRIMARY KEY,
                    paper_id TEXT NOT NULL,
                    paper_name TEXT NOT NULL,
                    paper_logo TEXT,
                    title TEXT NOT NULL,
                    snippet TEXT,
                    image_url TEXT,
                    article_url TEXT UNIQUE NOT NULL,
                    published_at INTEGER NOT NULL,
                    category TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_hd_pub ON headlines(published_at DESC);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_hd_cat ON headlines(category, published_at DESC);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_hd_paper ON headlines(paper_id, published_at DESC);")

            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS cached_articles (
                    url_hash TEXT PRIMARY KEY,
                    url TEXT UNIQUE NOT NULL,
                    title TEXT NOT NULL,
                    source_name TEXT NOT NULL,
                    author TEXT,
                    published_date TEXT,
                    hero_image_url TEXT,
                    paragraphs_json TEXT NOT NULL,
                    clean_html TEXT,
                    word_count INTEGER DEFAULT 0,
                    reading_time_minutes INTEGER DEFAULT 1,
                    cached_at INTEGER NOT NULL
                );
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_ca_url ON cached_articles(url);")

    def save_headlines(self, items: List[Dict[str, Any]]) -> int:
        if not items:
            return 0
        conn = self._get_conn()
        saved = 0
        now = _now_ms()
        with conn:
            for item in items:
                try:
                    conn.execute(
                        """
                        INSERT INTO headlines
                            (id, paper_id, paper_name, paper_logo, title, snippet, image_url, article_url, published_at, category, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(article_url) DO UPDATE SET
                            title = excluded.title,
                            snippet = excluded.snippet,
                            image_url = CASE WHEN excluded.image_url IS NOT NULL AND excluded.image_url != '' THEN excluded.image_url ELSE headlines.image_url END,
                            published_at = excluded.published_at;
                        """,
                        (
                            item["id"],
                            item["paper_id"],
                            item["paper_name"],
                            item.get("paper_logo") or "",
                            item["title"],
                            item.get("snippet") or "",
                            item.get("image_url") or "",
                            item["article_url"],
                            item["published_at"],
                            item["category"],
                            now,
                        ),
                    )
                    saved += 1
                except Exception as e:
                    logger.debug("Failed inserting headline %s: %s", item.get("article_url"), e)
        return saved

    def get_headlines(
        self,
        category: Optional[str] = None,
        paper_id: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        conn = self._get_conn()
        clauses = []
        params = []

        if category and category != "all":
            clauses.append("category = ?")
            params.append(category)

        if paper_id:
            clauses.append("paper_id = ?")
            params.append(paper_id)

        if query and query.strip():
            q_token = f"%{query.strip().lower()}%"
            clauses.append("(LOWER(title) LIKE ? OR LOWER(snippet) LIKE ?)")
            params.extend([q_token, q_token])

        where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        sql = f"""
            SELECT id, paper_id, paper_name, paper_logo, title, snippet, image_url,
                   article_url, published_at, category
            FROM headlines
            {where_sql}
            ORDER BY published_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        rows = conn.execute(sql, params).fetchall()
        now = _now_ms()
        results = []
        for r in rows:
            pub_ms = r["published_at"]
            diff_sec = max(0, int((now - pub_ms) / 1000))
            if diff_sec < 60:
                rel = "Just now"
            elif diff_sec < 3600:
                rel = f"{diff_sec // 60}m ago"
            elif diff_sec < 86400:
                rel = f"{diff_sec // 3600}h ago"
            else:
                rel = f"{diff_sec // 86400}d ago"

            results.append({
                "id": r["id"],
                "paperId": r["paper_id"],
                "paperName": r["paper_name"],
                "paperLogo": r["paper_logo"] or f"https://www.google.com/s2/favicons?domain={NEWSPAPER_MAP.get(r['paper_id'], {}).get('domain', '')}&sz=128",
                "title": r["title"],
                "snippet": r["snippet"] or "",
                "imageUrl": r["image_url"] or "",
                "articleUrl": r["article_url"],
                "publishedAt": pub_ms,
                "relativeTime": rel,
                "category": r["category"],
            })
        return results

    def get_cached_article(self, url: str) -> Optional[Dict[str, Any]]:
        conn = self._get_conn()
        url_hash = hashlib.sha256(url.strip().encode("utf-8")).hexdigest()
        row = conn.execute(
            "SELECT * FROM cached_articles WHERE url_hash = ? OR url = ?",
            (url_hash, url.strip()),
        ).fetchone()
        if not row:
            return None
        import json
        try:
            paragraphs = json.loads(row["paragraphs_json"])
        except Exception:
            paragraphs = []
        return {
            "title": row["title"],
            "sourceName": row["source_name"],
            "author": row["author"] or "",
            "publishedDate": row["published_date"] or "",
            "heroImageUrl": row["hero_image_url"] or "",
            "paragraphs": paragraphs,
            "cleanHtml": row["clean_html"] or "",
            "wordCount": row["word_count"],
            "readingTimeMinutes": row["reading_time_minutes"],
            "originalUrl": row["url"],
            "isCached": True,
        }

    def save_cached_article(self, article: Dict[str, Any]) -> None:
        conn = self._get_conn()
        import json
        url = article["originalUrl"].strip()
        url_hash = hashlib.sha256(url.encode("utf-8")).hexdigest()
        with conn:
            conn.execute(
                """
                INSERT INTO cached_articles
                    (url_hash, url, title, source_name, author, published_date, hero_image_url,
                     paragraphs_json, clean_html, word_count, reading_time_minutes, cached_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(url_hash) DO UPDATE SET
                    title = excluded.title,
                    source_name = excluded.source_name,
                    author = excluded.author,
                    published_date = excluded.published_date,
                    hero_image_url = excluded.hero_image_url,
                    paragraphs_json = excluded.paragraphs_json,
                    clean_html = excluded.clean_html,
                    word_count = excluded.word_count,
                    reading_time_minutes = excluded.reading_time_minutes,
                    cached_at = excluded.cached_at;
                """,
                (
                    url_hash,
                    url,
                    article["title"],
                    article["sourceName"],
                    article.get("author") or "",
                    article.get("publishedDate") or "",
                    article.get("heroImageUrl") or "",
                    json.dumps(article.get("paragraphs") or [], ensure_ascii=False),
                    article.get("cleanHtml") or "",
                    article.get("wordCount", 0),
                    article.get("readingTimeMinutes", 1),
                    _now_ms(),
                ),
            )

    def prune_old_headlines(self, max_days: int = 7) -> int:
        conn = self._get_conn()
        cutoff_ms = _now_ms() - (max_days * 86400 * 1000)
        with conn:
            cur = conn.execute("DELETE FROM headlines WHERE published_at < ?", (cutoff_ms,))
            return cur.rowcount


db = NewsDatabase(NEWS_DB_PATH)


# ---------------------------------------------------------------------------
# RSS/Atom Fetcher & XML Parser
# ---------------------------------------------------------------------------

class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.text_parts: List[str] = []

    def handle_data(self, data: str) -> None:
        cleaned = data.strip()
        if cleaned:
            self.text_parts.append(cleaned)

    def get_text(self) -> str:
        return " ".join(self.text_parts)


def strip_html(html_str: Optional[str]) -> str:
    if not html_str:
        return ""
    try:
        p = TextExtractor()
        p.feed(html_str)
        raw = p.get_text()
        return html.unescape(raw).strip()
    except Exception:
        # Fallback regex
        clean = re.sub(r"<[^>]+>", " ", html_str)
        return html.unescape(clean).strip()


def parse_rfc822_or_iso_date(date_str: Optional[str]) -> int:
    if not date_str:
        return _now_ms()
    from email.utils import parsedate_to_datetime
    try:
        dt = parsedate_to_datetime(date_str)
        return int(dt.timestamp() * 1000)
    except Exception:
        pass
    # Try ISO
    try:
        from datetime import datetime
        clean_iso = date_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(clean_iso)
        return int(dt.timestamp() * 1000)
    except Exception:
        return _now_ms()


def extract_image_from_item(item_node) -> Optional[str]:
    # 1. <media:content url="...">
    for tag in ["{http://search.yahoo.com/mrss/}content", "{http://search.yahoo.com/mrss/}thumbnail", "media:content", "media:thumbnail", "enclosure"]:
        node = item_node.find(tag)
        if node is not None:
            url = node.attrib.get("url")
            if url and any(url.lower().endswith(ext) or ("jpg" in url or "png" in url or "webp" in url) for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                return url

    # 2. Extract <img> src from description or content:encoded
    for child in item_node:
        if "description" in child.tag.lower() or "encoded" in child.tag.lower():
            text = child.text or ""
            img_match = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', text, re.IGNORECASE)
            if img_match:
                return img_match.group(1)

    return None


def find_first_tag(node, tags: List[str]):
    """Safely finds the first matching XML element without using boolean or (which breaks on leaf elements)."""
    for t in tags:
        el = node.find(t)
        if el is not None:
            return el
    return None


def get_element_text(el) -> str:
    """Extracts all text inside an XML element and its children (handles <a>, <span>, CDATA)."""
    if el is None:
        return ""
    try:
        return "".join(el.itertext()).strip()
    except Exception:
        return (el.text or "").strip()


def fetch_newspaper_feed(paper: Dict[str, Any]) -> List[Dict[str, Any]]:
    rss_url = paper.get("rssUrl")
    if not rss_url:
        return []

    req = urllib.request.Request(
        rss_url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 BhromonNews/2.0",
            "Accept": "application/rss+xml, application/xml, text/xml, */*",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = resp.read()
    except Exception as e:
        logger.warning("Feed fetch failed for %s (%s): %s", paper['name'], rss_url, e)
        return []

    import xml.etree.ElementTree as ET

    try:
        root = ET.fromstring(data)
    except Exception as e:
        logger.warning("XML parse error for %s: %s", paper['name'], e)
        return []

    items = []
    # RSS 2.0 / RDF items
    raw_items = root.findall(".//item")
    if not raw_items:
        # Atom feed entries
        raw_items = root.findall(".//{http://www.w3.org/2005/Atom}entry")
    if not raw_items:
        raw_items = root.findall(".//entry")

    now_ms = _now_ms()
    for node in raw_items[:40]:  # Up to top 40 items per paper
        title_el = find_first_tag(node, ["title", "{http://www.w3.org/2005/Atom}title"])
        if title_el is None:
            continue
        title = strip_html(get_element_text(title_el))
        if not title:
            continue

        link_el = find_first_tag(node, ["link", "{http://www.w3.org/2005/Atom}link"])
        link = ""
        if link_el is not None:
            link = get_element_text(link_el) or link_el.attrib.get("href", "")
        link = link.strip()
        if not link or not link.startswith("http"):
            continue

        desc_el = find_first_tag(node, [
            "description",
            "summary",
            "{http://www.w3.org/2005/Atom}summary",
            "{http://purl.org/rss/1.0/modules/content/}encoded",
        ])
        snippet = strip_html(get_element_text(desc_el))
        if len(snippet) > 280:
            snippet = snippet[:277] + "..."

        pub_el = find_first_tag(node, [
            "pubDate",
            "published",
            "{http://www.w3.org/2005/Atom}published",
            "{http://www.w3.org/2005/Atom}updated",
            "dc:date",
            "{http://purl.org/dc/elements/1.1/}date",
        ])
        pub_text = get_element_text(pub_el)
        pub_ms = parse_rfc822_or_iso_date(pub_text)

        img_url = extract_image_from_item(node)

        item_id = hashlib.sha256(link.encode("utf-8")).hexdigest()[:16]

        items.append({
            "id": item_id,
            "paper_id": paper["id"],
            "paper_name": paper["name"],
            "paper_logo": f"https://www.google.com/s2/favicons?domain={paper['domain']}&sz=128",
            "title": title,
            "snippet": snippet,
            "image_url": img_url,
            "article_url": link,
            "published_at": pub_ms,
            "category": paper["category"],
        })

    return items


# ---------------------------------------------------------------------------
# Background News Aggregator Worker
# ---------------------------------------------------------------------------

class NewsAggregator:
    def __init__(self) -> None:
        self.last_sync_ms: int = 0
        self.sync_lock = threading.Lock()
        self.is_syncing: bool = False

    def sync_all(self, background: bool = True) -> int:
        if self.sync_lock.locked():
            return 0
        if background:
            t = threading.Thread(target=self._run_sync, daemon=True)
            t.start()
            return 1
        return self._run_sync()

    def _run_sync(self) -> int:
        with self.sync_lock:
            self.is_syncing = True
            total_saved = 0
            start_time = time.time()
            logger.info("Starting newspaper headline sync...")

            # Fetch in parallel with thread pool
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
                future_to_paper = {
                    executor.submit(fetch_newspaper_feed, paper): paper
                    for paper in NEWSPAPER_CATALOG
                }
                for future in concurrent.futures.as_completed(future_to_paper):
                    paper = future_to_paper[future]
                    try:
                        items = future.result()
                        if items:
                            saved = db.save_headlines(items)
                            total_saved += saved
                    except Exception as e:
                        logger.error("Error aggregating %s: %s", paper["name"], e)

            # Prune headlines older than 7 days
            db.prune_old_headlines(max_days=7)

            self.last_sync_ms = _now_ms()
            self.is_syncing = False
            duration = round(time.time() - start_time, 2)
            logger.info("Newspaper headline sync finished: %d saved/updated in %ss", total_saved, duration)
            return total_saved


news_aggregator = NewsAggregator()


# ---------------------------------------------------------------------------
# Topic Clustering: "Same story, different papers"
# ---------------------------------------------------------------------------

STOP_WORDS = frozenset({
    # English
    "a", "an", "the", "in", "on", "at", "to", "for", "of", "and", "or", "is",
    "are", "was", "were", "with", "by", "as", "from", "be", "this", "that",
    "will", "says", "after", "over", "into", "it", "its", "up", "out", "no",
    # Bengali common
    "ও", "এবং", "বা", "কিন্তু", "না", "করে", "করা", "হয়েছে", "হবে", "হলে",
    "থেকে", "দিয়ে", "জন্য", "এর", "এক", "একটি", "পর", "নিয়ে", "যে", "কী",
    "বলেন", "দিল", "গেল", "নতুন", "আজ", "কাল", "এখন",
})


def tokenize_title(title: str) -> Set[str]:
    # Lowercase, strip punctuation
    clean = re.sub(r"[^\w\s\u0980-\u09FF]", " ", title.lower())
    tokens = {w.strip() for w in clean.split() if len(w.strip()) > 2 and w.strip() not in STOP_WORDS}
    return tokens


def cluster_headlines(headlines: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Groups headlines from 2+ distinct newspapers covering the same breaking story."""
    if not headlines:
        return []

    # Only inspect recent headlines (last 36 hours)
    recent = headlines[:80]
    clusters: List[Dict[str, Any]] = []
    used_ids: Set[str] = set()

    for i in range(len(recent)):
        h1 = recent[i]
        if h1["id"] in used_ids:
            continue
        toks1 = tokenize_title(h1["title"])
        if len(toks1) < 2:
            continue

        matched_items = [h1]
        distinct_papers = {h1["paperName"]}

        for j in range(i + 1, len(recent)):
            h2 = recent[j]
            if h2["id"] in used_ids:
                continue
            if h2["paperName"] in distinct_papers:
                continue  # Must be different newspapers

            toks2 = tokenize_title(h2["title"])
            if not toks2:
                continue

            intersection = toks1.intersection(toks2)
            # Match condition: at least 2 significant shared words and jaccard >= 0.28
            jaccard = len(intersection) / max(1, len(toks1.union(toks2)))
            if len(intersection) >= 2 or jaccard >= 0.30:
                matched_items.append(h2)
                distinct_papers.add(h2["paperName"])

        if len(distinct_papers) >= 2:
            for item in matched_items:
                used_ids.add(item["id"])
            clusters.append({
                "topic": matched_items[0]["title"],
                "headlineCount": len(matched_items),
                "papers": list(distinct_papers),
                "items": matched_items,
            })
            if len(clusters) >= 8:
                break

    return clusters


# ---------------------------------------------------------------------------
# Ad-Free Clean Reader Mode (Article Parser)
# ---------------------------------------------------------------------------

class ReadabilityExtractor(HTMLParser):
    """Zero-dependency HTML parser that strips ads, nav, banners and extracts clean paragraphs."""

    DISCARD_TAGS = frozenset({
        "script", "style", "noscript", "nav", "header", "footer", "aside",
        "iframe", "svg", "button", "form", "input", "select", "dialog",
        "embed", "object", "canvas", "audio", "video",
    })

    AD_CLASS_PATTERNS = re.compile(
        r"(advert|banner|sponsored|taboola|outbrain|google-ad|adsbygoogle|dfp|"
        r"popup|newsletter|subscription|cookie|modal|social-share|share-bar|"
        r"disqus|comment|related-news|sidebar|widget|promo)",
        re.IGNORECASE,
    )

    def __init__(self) -> None:
        super().__init__()
        self.tag_stack: List[Tuple[str, bool]] = []
        self.discard_depth = 0
        self.in_p = False
        self.current_p: List[str] = []
        self.paragraphs: List[str] = []
        self.og_title: Optional[str] = None
        self.og_image: Optional[str] = None
        self.og_site_name: Optional[str] = None
        self.author: Optional[str] = None
        self.pub_date: Optional[str] = None
        self.first_h1: Optional[str] = None
        self.in_h1 = False
        self.h1_parts: List[str] = []

    def handle_starttag(self, tag: str, attrs: List[Tuple[str, Optional[str]]]) -> None:
        attr_dict = {k.lower(): (v or "") for k, v in attrs}
        tag_lower = tag.lower()

        # Check metadata
        if tag_lower == "meta":
            prop = attr_dict.get("property", "").lower() or attr_dict.get("name", "").lower()
            content = attr_dict.get("content", "").strip()
            if prop in ("og:title", "twitter:title") and not self.og_title:
                self.og_title = html.unescape(content)
            elif prop in ("og:image", "twitter:image") and not self.og_image:
                self.og_image = content
            elif prop in ("og:site_name", "application-name") and not self.og_site_name:
                self.og_site_name = html.unescape(content)
            elif prop in ("author", "article:author") and not self.author:
                self.author = html.unescape(content)
            elif prop in ("article:published_time", "pubdate", "date") and not self.pub_date:
                self.pub_date = content
            return

        class_or_id = f"{attr_dict.get('class', '')} {attr_dict.get('id', '')}"
        is_discard = tag_lower in self.DISCARD_TAGS or bool(self.AD_CLASS_PATTERNS.search(class_or_id))

        if is_discard:
            self.discard_depth += 1
        self.tag_stack.append((tag_lower, is_discard))

        if self.discard_depth > 0:
            return

        if tag_lower == "h1" and not self.first_h1:
            self.in_h1 = True
            self.h1_parts = []

        if tag_lower == "p":
            self.in_p = True
            self.current_p = []

    def handle_endtag(self, tag: str) -> None:
        tag_lower = tag.lower()
        while self.tag_stack:
            t, was_discard = self.tag_stack.pop()
            if was_discard:
                self.discard_depth = max(0, self.discard_depth - 1)
            if t == tag_lower:
                break

        if tag_lower == "h1" and self.in_h1:
            self.in_h1 = False
            self.first_h1 = html.unescape(" ".join(self.h1_parts).strip())

        if tag_lower == "p" and self.in_p:
            self.in_p = False
            raw_text = html.unescape(" ".join(self.current_p).strip())
            # Clean paragraph filtering
            if len(raw_text) >= 20 and not self.AD_CLASS_PATTERNS.search(raw_text):
                self.paragraphs.append(raw_text)

    def handle_data(self, data: str) -> None:
        if self.discard_depth > 0:
            return
        cleaned = data.strip()
        if not cleaned:
            return
        if self.in_h1:
            self.h1_parts.append(cleaned)
        if self.in_p:
            self.current_p.append(cleaned)


def extract_adfree_article(url: str) -> Dict[str, Any]:
    """Fetches article URL and extracts ad-free readable typography."""
    # Check cache first
    cached = db.get_cached_article(url)
    if cached:
        return cached

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 BhromonNewsReader/2.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "bn,en-US,en;q=0.9",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            # Handle encoding
            charset = resp.headers.get_content_charset() or "utf-8"
            raw_bytes = resp.read()
            html_text = raw_bytes.decode(charset, errors="replace")
    except Exception as e:
        logger.error("Failed fetching article for reader %s: %s", url, e)
        raise HTTPException(status_code=502, detail=f"Failed to fetch article: {str(e)}")

    parser = ReadabilityExtractor()
    try:
        parser.feed(html_text)
    except Exception as e:
        logger.warning("Parser encountered soft error: %s", e)

    # Derive metadata
    title = parser.og_title or parser.first_h1 or "Untitled Story"
    domain = urllib.parse.urlparse(url).netloc.replace("www.", "")
    source_name = parser.og_site_name or domain.capitalize()

    # Calculate word count & reading time
    all_text = " ".join(parser.paragraphs)
    words = all_text.split()
    word_count = len(words)
    reading_time = max(1, round(word_count / 180))

    # Construct clean sanitized HTML
    clean_html_parts = [
        f"<article class='bhromon-clean-reader'>",
        f"<h1 class='reader-title'>{html.escape(title)}</h1>",
        f"<div class='reader-meta'><span>{html.escape(source_name)}</span>",
    ]
    if parser.author:
        clean_html_parts.append(f" • <span>{html.escape(parser.author)}</span>")
    clean_html_parts.append(f" • <span>{reading_time} min read</span></div>")

    if parser.og_image:
        clean_html_parts.append(f"<div class='reader-hero'><img src='{html.escape(parser.og_image)}' alt='Hero' /></div>")

    for p in parser.paragraphs:
        clean_html_parts.append(f"<p>{html.escape(p)}</p>")

    clean_html_parts.append("</article>")
    clean_html = "".join(clean_html_parts)

    article = {
        "title": title,
        "sourceName": source_name,
        "author": parser.author or "",
        "publishedDate": parser.pub_date or "",
        "heroImageUrl": parser.og_image or "",
        "paragraphs": parser.paragraphs,
        "cleanHtml": clean_html,
        "wordCount": word_count,
        "readingTimeMinutes": reading_time,
        "originalUrl": url,
        "isCached": False,
    }

    # Save to SQLite cache
    try:
        db.save_cached_article(article)
    except Exception as e:
        logger.warning("Failed caching article: %s", e)

    return article


# ---------------------------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------------------------

@router.get("/papers")
def get_newspaper_directory(category: Optional[str] = None):
    """Returns the full categorized directory of newspapers."""
    papers = NEWSPAPER_CATALOG
    if category and category != "all":
        papers = [p for p in papers if p["category"] == category]
    return {
        "total": len(papers),
        "papers": papers,
    }


@router.get("/headlines")
def get_headlines(
    category: Optional[str] = Query(None, description="Category filter (all, bangla_dailies, english_dailies, online_portals, world_tech, sports)"),
    paper_id: Optional[str] = Query(None, description="Specific newspaper id filter"),
    query: Optional[str] = Query(None, description="Search query string"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    refresh: bool = Query(False, description="Trigger on-demand background sync"),
):
    """Returns live headlines, category filters, and 'Same story, different papers' topic clusters."""
    # If database is empty or refresh requested, trigger background aggregation
    if refresh or news_aggregator.last_sync_ms == 0:
        news_aggregator.sync_all(background=True)

    items = db.get_headlines(
        category=category,
        paper_id=paper_id,
        query=query,
        limit=limit,
        offset=offset,
    )

    # Compute clusters from current headlines
    clusters = cluster_headlines(items) if not query else []

    return {
        "count": len(items),
        "limit": limit,
        "offset": offset,
        "updatedAt": news_aggregator.last_sync_ms,
        "isSyncing": news_aggregator.is_syncing,
        "clusters": clusters,
        "items": items,
    }


@router.get("/reader")
def get_reader_article(url: str = Query(..., description="The original article URL to read ad-free")):
    """Fetches an article and returns an ad-free clean reader representation."""
    if not url or not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid article URL")
    return extract_adfree_article(url)


@router.post("/sync")
def trigger_news_sync():
    """Manually triggers headline synchronization across all newspapers."""
    news_aggregator.sync_all(background=True)
    return {"status": "sync_triggered", "timestamp": _now_ms()}


# ---------------------------------------------------------------------------
# Ad-Free Live Web Proxy for Embeddable Newspaper Browsing
# ---------------------------------------------------------------------------

_AD_SCRIPT_REGEX = re.compile(
    r'<script\b[^>]*?(?:googlesyndication|googleadservices|doubleclick|taboola|outbrain|criteo|adnxs|pubmatic|rubiconproject|smartadserver|adroll|popads|adcash|exponential|inmobi|adcolony|chartbeat|mgid|revcontent|adservice)[^>]*?>.*?</script>',
    re.IGNORECASE | re.DOTALL,
)

_INLINE_AD_SCRIPT_REGEX = re.compile(
    r'<script\b[^>]*?>.*?(?:adsbygoogle|googletag\.display|googletag\.enableServices).*?</script>',
    re.IGNORECASE | re.DOTALL,
)

_AD_IFRAME_REGEX = re.compile(
    r'<iframe\b[^>]*?(?:doubleclick|googlesyndication|adservice|taboola|outbrain|criteo|adnxs)[^>]*?>.*?</iframe>',
    re.IGNORECASE | re.DOTALL,
)

_BHROMON_ADBLOCK_CSS = """
<style id="bhromon-adblock-injected">
  html, body {
    background-color: #ffffff !important;
    color: #111111 !important;
  }
  .ads, .ad, .ad-banner, .advertisement, .ad-container, .ad-wrapper,
  .ad-box, .ad-slot, .ad-placeholder, .adsbygoogle, [id^="google_ads_"],
  [id^="div-gpt-ad"], iframe[src*="doubleclick"], iframe[src*="adservice"],
  iframe[src*="googlesyndication"], .taboola, .outbrain, .interstitial-ad,
  .sticky-ad, .floating-ad, .popup-overlay, .ad-flyout, #leaderboard-ad,
  .top-ad, .bottom-sticky-ad, .modal-ad, [class*="advertisement" i],
  [class*="ad-unit" i], [id*="ad_holder" i], [id*="ad-container" i],
  .ads-placeholder, [aria-label*="advertisement" i], .native-ad-unit,
  .ad-block, .sponsored-post, [data-ad], [data-ad-unit],
  .dfp-tag, .ad_wrapper, .ad_container, .advert, .advert-box,
  #ad-interstitial, .interstitial, .ad-popup, .floating-banner {
    display: none !important;
    visibility: hidden !important;
    height: 0 !important;
    width: 0 !important;
    opacity: 0 !important;
    pointer-events: none !important;
    position: absolute !important;
    left: -9999px !important;
    margin: 0 !important;
    padding: 0 !important;
  }
</style>
"""

_BHROMON_LINK_REWRITER_JS = """
<script id="bhromon-link-rewriter">
  (function() {
    window.open = function(u) { console.log('[Bhromon AdBlock] Blocked popup:', u); return null; };
    document.addEventListener('click', function(e) {
      var target = e.target;
      while (target && target.tagName !== 'A') {
        target = target.parentElement;
      }
      if (target && target.href && !target.href.startsWith('javascript:') && !target.href.startsWith('#')) {
        var href = target.href;
        if (!href.includes('/api/news/proxy?url=')) {
          e.preventDefault();
          var proxyUrl = 'https://bhromon.fun/api/news/proxy?url=' + encodeURIComponent(href);
          window.location.href = proxyUrl;
        }
      }
    }, true);
  })();
</script>
"""


@router.get("/proxy")
def proxy_newspaper(
    url: str = Query(..., description="Target newspaper URL to fetch and strip ads from"),
):
    """Fetches a newspaper webpage, strips ad scripts, popups, and banners,
    removes X-Frame-Options/CSP restrictions, and returns embeddable ad-free HTML."""
    if not url or not (url.startswith("http://") or url.startswith("https://")):
        raise HTTPException(status_code=400, detail="Invalid URL: Scheme must be http or https")

    parsed = urllib.parse.urlparse(url)
    hostname = (parsed.hostname or "").lower()
    if (
        hostname in ("localhost", "127.0.0.1", "0.0.0.0", "::1")
        or hostname.startswith("192.168.")
        or hostname.startswith("10.")
        or hostname.endswith(".internal")
    ):
        raise HTTPException(status_code=403, detail="Prohibited private network host")

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 BhromonAdBlockBrowser/2.0"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "bn,en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, identity",
            "Referer": f"{parsed.scheme}://{parsed.netloc}/",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            content_encoding = resp.headers.get("Content-Encoding", "").lower()
            raw_bytes = resp.read()
            if "gzip" in content_encoding:
                try:
                    raw_bytes = gzip.decompress(raw_bytes)
                except Exception as gz_err:
                    logger.warning("Gzip decompress fallback for %s: %s", url, gz_err)

            charset = resp.headers.get_content_charset() or "utf-8"
            html_text = raw_bytes.decode(charset, errors="replace")
    except Exception as e:
        logger.warning("Failed proxying newspaper URL %s: %s", url, e)
        # Return a responsive embeddable fallback card so Cloudflare never sets X-Frame-Options: SAMEORIGIN
        clean_domain = parsed.netloc or url
        fallback_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(clean_domain)} - Bhromon News</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #0D1117;
      color: #E2E8F0;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }}
    .card {{
      background: #161B22;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 20px;
      padding: 36px 28px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 12px 36px rgba(0,0,0,0.6);
    }}
    .shield-badge {{
      width: 64px;
      height: 64px;
      margin: 0 auto 20px;
      border-radius: 50%;
      background: rgba(0, 208, 158, 0.12);
      display: flex;
      align-items: center;
      justify-content: center;
      color: #00D09E;
      font-size: 28px;
    }}
    h1 {{ font-size: 20px; font-weight: 700; color: #FFFFFF; margin-bottom: 8px; }}
    .domain {{ font-size: 14px; color: #00D09E; margin-bottom: 18px; font-weight: 600; word-break: break-all; }}
    p {{ font-size: 13.5px; color: #94A3B8; line-height: 1.6; margin-bottom: 26px; }}
    .btn-group {{ display: flex; flex-direction: column; gap: 12px; }}
    .btn {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 13px 20px;
      border-radius: 12px;
      font-size: 14px;
      font-weight: 600;
      text-decoration: none;
      transition: all 0.2s ease;
      cursor: pointer;
    }}
    .btn-primary {{
      background: #00D09E;
      color: #071912;
      border: none;
    }}
    .btn-primary:hover {{ background: #00b98c; }}
    .btn-secondary {{
      background: transparent;
      color: #FFFFFF;
      border: 1px solid rgba(255, 255, 255, 0.2);
    }}
    .btn-secondary:hover {{ background: rgba(255, 255, 255, 0.08); }}
  </style>
</head>
<body>
  <div class="card">
    <div class="shield-badge">🛡️</div>
    <h1>Direct Protection Active</h1>
    <div class="domain">{html.escape(clean_domain)}</div>
    <p>
      This newspaper employs automated Cloudflare or bot protection that restricts in-frame web embedding.
      You can open it directly in a dedicated tab or read it in distraction-free Reader mode.
    </p>
    <div class="btn-group">
      <a href="{html.escape(url, quote=True)}" target="_blank" rel="noopener noreferrer" class="btn btn-primary">
        Open {html.escape(clean_domain)} ↗
      </a>
      <a href="/api/news/reader-view?url={urllib.parse.quote_plus(url)}" class="btn btn-secondary">
        Distraction-Free Reader Mode 📖
      </a>
    </div>
  </div>
</body>
</html>"""
        return Response(
            content=fallback_html,
            media_type="text/html; charset=utf-8",
            status_code=200,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache",
                "Content-Security-Policy": "frame-ancestors *",
            },
        )

    # 1. Strip external ad network script tags
    cleaned_html = _AD_SCRIPT_REGEX.sub("", html_text)
    # 2. Strip inline ad display scripts
    cleaned_html = _INLINE_AD_SCRIPT_REGEX.sub("", cleaned_html)
    # 3. Strip ad iframes
    cleaned_html = _AD_IFRAME_REGEX.sub("", cleaned_html)

    # 4. Inject <base href="..."> so all relative paths (css, js, images) resolve accurately
    base_tag = f'<base href="{html.escape(url, quote=True)}">'
    if "<head" in cleaned_html.lower():
        # Inject right after <head ...>
        cleaned_html = re.sub(
            r'(<head\b[^>]*>)',
            r'\1' + base_tag + _BHROMON_ADBLOCK_CSS,
            cleaned_html,
            count=1,
            flags=re.IGNORECASE,
        )
    else:
        cleaned_html = base_tag + _BHROMON_ADBLOCK_CSS + cleaned_html

    # 5. Inject link interceptor before </body>
    if "</body" in cleaned_html.lower():
        cleaned_html = re.sub(
            r'(</body\b[^>]*>)',
            _BHROMON_LINK_REWRITER_JS + r'\1',
            cleaned_html,
            count=1,
            flags=re.IGNORECASE,
        )
    else:
        cleaned_html += _BHROMON_LINK_REWRITER_JS

    return Response(
        content=cleaned_html,
        media_type="text/html; charset=utf-8",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Cache-Control": "public, max-age=120",
            # Remove any frame restriction headers
            "X-Frame-Options": "ALLOWALL",
            "Content-Security-Policy": "frame-ancestors *",
        },
    )


@router.get("/reader-view", response_class=HTMLResponse)
def get_reader_html_view(
    url: str = Query(..., description="Target article URL to render in clean reader mode"),
):
    """Renders the extracted clean article as an aesthetic, responsive reader webpage."""
    article = _extract_clean_article(url)
    hero_img_tag = f'<img src="{html.escape(article.heroImageUrl, quote=True)}" class="hero-img" alt="Hero Image">' if article.heroImageUrl else ""
    paragraphs_html = "".join(f"<p>{html.escape(p)}</p>" for p in article.paragraphs)
    
    reader_page = f"""<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(article.title)} - Bhromon Reader</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Kalpurush", "SolaimanLipi", "Segoe UI", Roboto, sans-serif;
      background: #0B0E12;
      color: #E2E8F0;
      line-height: 1.85;
      padding: 24px 16px;
      display: flex;
      justify-content: center;
    }}
    .container {{
      max-width: 680px;
      width: 100%;
    }}
    .back-bar {{
      margin-bottom: 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}
    .badge {{
      background: rgba(0, 208, 158, 0.15);
      color: #00D09E;
      padding: 4px 12px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
    }}
    .source {{
      font-size: 13px;
      color: #94A3B8;
    }}
    h1 {{
      font-size: 26px;
      font-weight: 800;
      color: #FFFFFF;
      line-height: 1.35;
      margin-bottom: 16px;
    }}
    .hero-img {{
      width: 100%;
      max-height: 380px;
      object-fit: cover;
      border-radius: 14px;
      margin-bottom: 24px;
    }}
    p {{
      font-size: 17px;
      color: #CBD5E1;
      margin-bottom: 18px;
      text-align: justify;
    }}
    .footer-bar {{
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
      display: flex;
      justify-content: space-between;
      font-size: 13px;
      color: #64748B;
    }}
    a {{
      color: #00D09E;
      text-decoration: none;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="back-bar">
      <span class="badge">Ad-Free Reader</span>
      <span class="source">{html.escape(article.sourceName or "News")}</span>
    </div>
    <h1>{html.escape(article.title)}</h1>
    {hero_img_tag}
    <div class="content">
      {paragraphs_html or "<p>Could not extract readable article text. You may visit the official website below.</p>"}
    </div>
    <div class="footer-bar">
      <span>Read via Bhromon</span>
      <a href="{html.escape(url, quote=True)}" target="_blank" rel="noopener">Open Source ↗</a>
    </div>
  </div>
</body>
</html>"""
    return HTMLResponse(
        content=reader_page,
        status_code=200,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=300",
            "Content-Security-Policy": "frame-ancestors *",
        },
    )

