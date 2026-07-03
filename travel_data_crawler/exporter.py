"""
Bhromon Travel Crawler — Export collected data to JSON and CSV
for easy import into the Bhromon app's Firestore database.
"""
import os
import json
import csv
import sqlite3
from datetime import datetime

from config import EXPORTS_DIR, DB_PATH
from database import get_db


def export_articles_json():
    conn = get_db()
    rows = conn.execute("""
        SELECT id, url, source_name, source_type, language, title, summary,
               author, published_at, keywords, cover_image, word_count, destination
        FROM articles WHERE status='ok'
        ORDER BY crawled_at DESC
    """).fetchall()
    conn.close()

    out = []
    for r in rows:
        out.append({
            "id": r["id"],
            "url": r["url"],
            "source": r["source_name"],
            "type": r["source_type"],
            "language": r["language"],
            "title": r["title"],
            "summary": r["summary"],
            "author": r["author"],
            "publishedAt": r["published_at"],
            "keywords": json.loads(r["keywords"] or "[]"),
            "coverImage": r["cover_image"],
            "wordCount": r["word_count"],
            "destination": r["destination"],
        })

    path = os.path.join(EXPORTS_DIR, "articles.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"[Export] Articles JSON → {path} ({len(out)} records)")
    return path


def export_videos_json():
    conn = get_db()
    rows = conn.execute("""
        SELECT video_id, platform, title, description, channel, url,
               thumbnail_path, duration, view_count, published_at, keywords
        FROM videos ORDER BY crawled_at DESC
    """).fetchall()
    conn.close()

    out = []
    for r in rows:
        out.append({
            "videoId": r["video_id"],
            "platform": r["platform"],
            "title": r["title"],
            "description": r["description"],
            "channel": r["channel"],
            "url": r["url"],
            "thumbnailPath": r["thumbnail_path"],
            "duration": r["duration"],
            "viewCount": r["view_count"],
            "publishedAt": r["published_at"],
            "keywords": json.loads(r["keywords"] or "[]"),
        })

    path = os.path.join(EXPORTS_DIR, "videos.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"[Export] Videos JSON → {path} ({len(out)} records)")
    return path


def export_facebook_json():
    conn = get_db()
    rows = conn.execute("""
        SELECT post_id, page, content, post_date, likes, comments, shares, images, links
        FROM facebook_posts ORDER BY crawled_at DESC
    """).fetchall()
    conn.close()

    out = []
    for r in rows:
        out.append({
            "postId": r["post_id"],
            "page": r["page"],
            "content": r["content"],
            "postDate": r["post_date"],
            "likes": r["likes"],
            "comments": r["comments"],
            "shares": r["shares"],
            "images": json.loads(r["images"] or "[]"),
            "links": json.loads(r["links"] or "[]"),
        })

    path = os.path.join(EXPORTS_DIR, "facebook_posts.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"[Export] Facebook JSON → {path} ({len(out)} records)")
    return path


def export_articles_csv():
    conn = get_db()
    rows = conn.execute("""
        SELECT url, source_name, source_type, language, title, summary,
               author, published_at, word_count, destination
        FROM articles WHERE status='ok'
    """).fetchall()
    conn.close()

    path = os.path.join(EXPORTS_DIR, "articles.csv")
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["URL", "Source", "Type", "Language", "Title", "Summary",
                         "Author", "Published", "WordCount", "Destination"])
        for r in rows:
            writer.writerow([r["url"], r["source_name"], r["source_type"], r["language"],
                             r["title"], r["summary"], r["author"], r["published_at"],
                             r["word_count"], r["destination"]])

    print(f"[Export] Articles CSV → {path}")
    return path


def generate_html_report():
    """Generate a visual HTML summary report of collected data."""
    from database import get_stats
    stats = get_stats()

    conn = get_db()
    top_articles = conn.execute("""
        SELECT title, source_name, destination, cover_image, url, summary
        FROM articles WHERE status='ok' AND cover_image IS NOT NULL
        ORDER BY word_count DESC LIMIT 20
    """).fetchall()
    top_videos = conn.execute("""
        SELECT title, channel, url, thumbnail_path, view_count
        FROM videos ORDER BY view_count DESC LIMIT 20
    """).fetchall()
    conn.close()

    def img_tag(path, alt="", width=300):
        if path and os.path.exists(path):
            # Convert to relative path for HTML
            rel = os.path.relpath(path, EXPORTS_DIR).replace("\\", "/")
            return f'<img src="../{rel}" alt="{alt}" style="width:{width}px;height:200px;object-fit:cover;border-radius:8px;">'
        return '<div style="width:300px;height:200px;background:#1a2a1a;border-radius:8px;display:flex;align-items:center;justify-content:center;color:#52B788;">No Image</div>'

    article_cards = ""
    for a in top_articles:
        article_cards += f"""
        <div class="card">
            {img_tag(a['cover_image'], a['title'])}
            <div class="card-body">
                <span class="badge">{a['destination'] or 'Bangladesh'}</span>
                <h3><a href="{a['url']}" target="_blank">{a['title'][:80]}</a></h3>
                <p>{a['summary'][:200] if a['summary'] else ''}</p>
                <small>📰 {a['source_name']}</small>
            </div>
        </div>"""

    video_cards = ""
    for v in top_videos:
        video_cards += f"""
        <div class="card">
            {img_tag(v['thumbnail_path'], v['title'])}
            <div class="card-body">
                <span class="badge youtube">YouTube</span>
                <h3><a href="{v['url']}" target="_blank">{v['title'][:80]}</a></h3>
                <small>📺 {v['channel']} · 👁 {v['view_count']:,}</small>
            </div>
        </div>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Bhromon Travel Data — Crawl Report</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Segoe UI', sans-serif; background: #050C08; color: #ECF0F1; padding: 24px; }}
  h1 {{ font-size: 2em; color: #52B788; margin-bottom: 4px; }}
  .subtitle {{ color: #aaa; margin-bottom: 32px; }}
  .stats {{ display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 40px; }}
  .stat-card {{ background: #0D1A12; border: 1px solid #1E3A26; border-radius: 12px; padding: 20px 28px; min-width: 140px; }}
  .stat-card .num {{ font-size: 2.4em; font-weight: bold; color: #52B788; }}
  .stat-card .label {{ color: #aaa; font-size: 0.85em; margin-top: 4px; }}
  h2 {{ color: #52B788; font-size: 1.3em; margin: 32px 0 16px; letter-spacing: 1px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; }}
  .card {{ background: #0D1A12; border: 1px solid #1E3A26; border-radius: 12px; overflow: hidden; }}
  .card-body {{ padding: 14px; }}
  .card-body h3 {{ font-size: 0.95em; margin: 8px 0 6px; }}
  .card-body h3 a {{ color: #ECF0F1; text-decoration: none; }}
  .card-body h3 a:hover {{ color: #52B788; }}
  .card-body p {{ color: #aaa; font-size: 0.82em; line-height: 1.5; }}
  .card-body small {{ color: #52B788; font-size: 0.8em; }}
  .badge {{ display: inline-block; background: #1B4332; color: #52B788; border-radius: 6px; padding: 2px 8px; font-size: 0.75em; font-weight: bold; margin-bottom: 6px; }}
  .badge.youtube {{ background: #2a0a0a; color: #ff4444; }}
  footer {{ text-align: center; color: #555; margin-top: 60px; font-size: 0.85em; }}
</style>
</head>
<body>
<h1>ভ্রমণ · Bhromon — Travel Data Collection</h1>
<p class="subtitle">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')} · Bangladesh Travel Intelligence</p>

<div class="stats">
  <div class="stat-card"><div class="num">{stats['articles']}</div><div class="label">Articles</div></div>
  <div class="stat-card"><div class="num">{stats['images']}</div><div class="label">Images</div></div>
  <div class="stat-card"><div class="num">{stats['videos']}</div><div class="label">Videos</div></div>
  <div class="stat-card"><div class="num">{stats['facebook_posts']}</div><div class="label">FB Posts</div></div>
  <div class="stat-card"><div class="num" style="color:#ff6b6b">{stats['errors']}</div><div class="label">Errors</div></div>
</div>

<h2>📰 TOP ARTICLES & BLOGS</h2>
<div class="grid">{article_cards}</div>

<h2>🎬 TOP YOUTUBE VIDEOS</h2>
<div class="grid">{video_cards}</div>

<footer>Bhromon Travel Crawler · Data collected for Bhromon App Firestore import</footer>
</body>
</html>"""

    path = os.path.join(EXPORTS_DIR, "report.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[Export] HTML Report → {path}")
    return path


def run_all_exports():
    os.makedirs(EXPORTS_DIR, exist_ok=True)
    export_articles_json()
    export_videos_json()
    export_facebook_json()
    export_articles_csv()
    generate_html_report()
    print("\n[Export] All exports complete.")
