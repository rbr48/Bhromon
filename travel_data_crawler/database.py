"""
Bhromon Travel Crawler — SQLite Database Manager
Stores all crawled articles, images, and video metadata.
"""
import sqlite3
import json
import os
from datetime import datetime
from config import DB_PATH


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    conn = get_db()
    c = conn.cursor()
    c.executescript("""
        CREATE TABLE IF NOT EXISTS articles (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            url         TEXT    UNIQUE NOT NULL,
            source_name TEXT,
            source_type TEXT,   -- news / blog / facebook / review
            language    TEXT,
            title       TEXT,
            content     TEXT,
            summary     TEXT,
            author      TEXT,
            published_at TEXT,
            crawled_at  TEXT    DEFAULT (datetime('now')),
            keywords    TEXT,   -- JSON array
            images      TEXT,   -- JSON array of local image paths
            cover_image TEXT,
            word_count  INTEGER DEFAULT 0,
            destination TEXT,   -- e.g., Cox's Bazar
            status      TEXT    DEFAULT 'ok'
        );

        CREATE TABLE IF NOT EXISTS images (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            article_id  INTEGER REFERENCES articles(id),
            url         TEXT    UNIQUE NOT NULL,
            local_path  TEXT,
            caption     TEXT,
            width       INTEGER,
            height      INTEGER,
            size_bytes  INTEGER,
            crawled_at  TEXT    DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS videos (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            video_id    TEXT    UNIQUE NOT NULL,
            platform    TEXT,   -- youtube / facebook
            title       TEXT,
            description TEXT,
            channel     TEXT,
            url         TEXT,
            thumbnail_path TEXT,
            duration    INTEGER,
            view_count  INTEGER,
            published_at TEXT,
            keywords    TEXT,
            crawled_at  TEXT    DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS facebook_posts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            post_id     TEXT    UNIQUE,
            page        TEXT,
            content     TEXT,
            post_date   TEXT,
            likes       INTEGER DEFAULT 0,
            comments    INTEGER DEFAULT 0,
            shares      INTEGER DEFAULT 0,
            images      TEXT,   -- JSON array of local paths
            links       TEXT,
            crawled_at  TEXT    DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS crawl_log (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            source      TEXT,
            url         TEXT,
            status      TEXT,
            message     TEXT,
            crawled_at  TEXT    DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_articles_source ON articles(source_name);
        CREATE INDEX IF NOT EXISTS idx_articles_destination ON articles(destination);
        CREATE INDEX IF NOT EXISTS idx_articles_lang ON articles(language);
        CREATE INDEX IF NOT EXISTS idx_images_article ON images(article_id);
    """)
    conn.commit()
    conn.close()
    print("[DB] Database initialised.")


def url_already_crawled(url: str) -> bool:
    conn = get_db()
    row = conn.execute("SELECT 1 FROM articles WHERE url=?", (url,)).fetchone()
    conn.close()
    return row is not None


def save_article(data: dict) -> int:
    conn = get_db()
    try:
        c = conn.cursor()
        c.execute("""
            INSERT OR REPLACE INTO articles
            (url, source_name, source_type, language, title, content, summary,
             author, published_at, keywords, images, cover_image, word_count, destination)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            data.get("url"), data.get("source_name"), data.get("source_type"),
            data.get("language"), data.get("title"), data.get("content"),
            data.get("summary"), data.get("author"), data.get("published_at"),
            json.dumps(data.get("keywords", []), ensure_ascii=False),
            json.dumps(data.get("images", []), ensure_ascii=False),
            data.get("cover_image"),
            data.get("word_count", 0),
            data.get("destination"),
        ))
        conn.commit()
        return c.lastrowid
    finally:
        conn.close()


def save_image(article_id: int, url: str, local_path: str,
               caption: str = "", width: int = 0, height: int = 0, size_bytes: int = 0):
    conn = get_db()
    try:
        conn.execute("""
            INSERT OR IGNORE INTO images (article_id, url, local_path, caption, width, height, size_bytes)
            VALUES (?,?,?,?,?,?,?)
        """, (article_id, url, local_path, caption, width, height, size_bytes))
        conn.commit()
    finally:
        conn.close()


def save_video(data: dict):
    conn = get_db()
    try:
        conn.execute("""
            INSERT OR IGNORE INTO videos
            (video_id, platform, title, description, channel, url,
             thumbnail_path, duration, view_count, published_at, keywords)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, (
            data.get("video_id"), data.get("platform"), data.get("title"),
            data.get("description"), data.get("channel"), data.get("url"),
            data.get("thumbnail_path"), data.get("duration"),
            data.get("view_count"), data.get("published_at"),
            json.dumps(data.get("keywords", []), ensure_ascii=False),
        ))
        conn.commit()
    finally:
        conn.close()


def save_facebook_post(data: dict):
    conn = get_db()
    try:
        conn.execute("""
            INSERT OR IGNORE INTO facebook_posts
            (post_id, page, content, post_date, likes, comments, shares, images, links)
            VALUES (?,?,?,?,?,?,?,?,?)
        """, (
            data.get("post_id"), data.get("page"), data.get("content"),
            data.get("post_date"), data.get("likes", 0), data.get("comments", 0),
            data.get("shares", 0),
            json.dumps(data.get("images", []), ensure_ascii=False),
            json.dumps(data.get("links", []), ensure_ascii=False),
        ))
        conn.commit()
    finally:
        conn.close()


def log_crawl(source: str, url: str, status: str, message: str = ""):
    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO crawl_log (source, url, status, message) VALUES (?,?,?,?)",
            (source, url, status, message)
        )
        conn.commit()
    finally:
        conn.close()


def get_stats() -> dict:
    conn = get_db()
    stats = {
        "articles":       conn.execute("SELECT COUNT(*) FROM articles").fetchone()[0],
        "images":         conn.execute("SELECT COUNT(*) FROM images").fetchone()[0],
        "videos":         conn.execute("SELECT COUNT(*) FROM videos").fetchone()[0],
        "facebook_posts": conn.execute("SELECT COUNT(*) FROM facebook_posts").fetchone()[0],
        "errors":         conn.execute("SELECT COUNT(*) FROM crawl_log WHERE status='error'").fetchone()[0],
    }
    conn.close()
    return stats
