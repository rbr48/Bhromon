"""
Bhromon Travel Crawler — RSS-based article scraper.
Uses feedparser for discovery + newspaper3k for full article extraction.
Handles Google News redirect URLs properly.
"""
import os
import re
import sys
import hashlib
import time
import random
from urllib.parse import urljoin, urlparse, unquote
from datetime import datetime
from typing import Optional

import feedparser
import requests
from bs4 import BeautifulSoup

try:
    import newspaper
    from newspaper import Article as NpArticle
    HAS_NEWSPAPER = True
except ImportError:
    HAS_NEWSPAPER = False

from config import (RSS_FEEDS, TRAVEL_KEYWORDS, IMAGES_DIR, NEWS_DIR, BLOGS_DIR,
                    RATE_LIMITS, USER_AGENTS)
from http_utils import make_session, download_image
from database import url_already_crawled, save_article, save_image, log_crawl
from browser_utils import BrowserContextManager


# ─── Helpers ────────────────────────────────────────────────────────────────────

def _slug(text: str, maxlen: int = 80) -> str:
    text = re.sub(r'[^\w\s-]', '', str(text).lower())
    text = re.sub(r'[\s_]+', '-', text).strip('-')
    return text[:maxlen] or "article"


def _is_travel_related(text: str) -> bool:
    t = text.lower()
    for kw in TRAVEL_KEYWORDS:
        # For short keywords, require word boundaries to avoid false positives (e.g. 'Ruma' in 'Ruman')
        if len(kw) <= 5:
            if re.search(r'\b' + re.escape(kw.lower()) + r'\b', t):
                return True
        else:
            if kw.lower() in t:
                return True
    return False


def _detect_destination(text: str) -> Optional[str]:
    t = text.lower()
    for kw in TRAVEL_KEYWORDS:
        if len(kw) > 5 and kw.lower() in t:
            return kw
    return None


def _article_dir(source_type: str, source_name: str) -> str:
    folder = NEWS_DIR if source_type == "news" else BLOGS_DIR
    safe = re.sub(r'[^\w]', '_', source_name)[:40]
    d = os.path.join(folder, safe)
    os.makedirs(d, exist_ok=True)
    return d


def _image_dir(url: str) -> str:
    h = hashlib.md5(url.encode()).hexdigest()[:8]
    d = os.path.join(IMAGES_DIR, h)
    os.makedirs(d, exist_ok=True)
    return d


# ─── Google News URL resolver ────────────────────────────────────────────────────

def resolve_google_news_url(gn_url: str, browser_manager: BrowserContextManager) -> str:
    """
    Google News RSS links (CBMi...) don't 301-redirect easily anymore.
    Uses Playwright to navigate to the link and extracts the final URL it lands on.
    """
    if "news.google.com" not in gn_url:
        return gn_url

    try:
        page = browser_manager.new_page()
        # Wait until there are no network connections for at least 500ms, ensuring redirects finish
        page.goto(gn_url, wait_until="networkidle", timeout=20000)
        
        final_url = page.url
        page.close()
        
        if "news.google.com" in final_url and "consent" not in final_url:
            return final_url
            
        return final_url

    except Exception as e:
        print(f"    [Browser] resolve_google_news_url failed: {e}")

    return gn_url  # Return original if all methods fail


# ─── Article extraction ──────────────────────────────────────────────────────────

def extract_with_newspaper(url: str) -> Optional[dict]:
    if not HAS_NEWSPAPER:
        return None
    try:
        config = newspaper.Config()
        config.browser_user_agent = random.choice(USER_AGENTS)
        config.request_timeout = RATE_LIMITS["timeout_seconds"]
        config.fetch_images = True
        config.memoize_articles = False

        art = NpArticle(url, config=config)
        art.download()
        art.parse()

        if not art.text or len(art.text.strip()) < 80:
            return None

        return {
            "title":        art.title or "",
            "content":      art.text,
            "author":       ", ".join(art.authors) if art.authors else "",
            "published_at": art.publish_date.isoformat() if art.publish_date else "",
            "top_image":    art.top_image or "",
            "images":       [i for i in list(art.images)[:12] if i.startswith("http")],
            "summary":      art.text[:500],
        }
    except Exception as e:
        return None


def extract_with_bs4(url: str, session) -> Optional[dict]:
    try:
        resp = session.get(url, timeout=RATE_LIMITS["timeout_seconds"])
        if not resp or resp.status_code != 200:
            return None
        soup = BeautifulSoup(resp.text, "lxml")

        title = ""
        for sel in ["h1", ".article-title", ".post-title", ".headline", "title"]:
            el = soup.select_one(sel)
            if el:
                title = el.get_text(strip=True)
                break

        content = ""
        for sel in ["article", ".article-body", ".post-body", ".entry-content",
                    ".content-body", ".story-detail", "main .content", "[class*='article']",
                    ".single-post-content", ".news-content", ".details-body"]:
            el = soup.select_one(sel)
            if el:
                for tag in el.select("nav,script,style,aside,.advertisement,.ad,.share"):
                    tag.decompose()
                content = el.get_text("\n", strip=True)
                if len(content) > 150:
                    break

        if not content:
            body = soup.find("body")
            if body:
                for tag in body.select("nav,header,footer,script,style,.menu"):
                    tag.decompose()
                content = body.get_text("\n", strip=True)[:4000]

        imgs = []
        for img in soup.select("article img, main img, .content img"):
            src = img.get("src") or img.get("data-src") or img.get("data-lazy-src", "")
            if src and not src.startswith("data:") and src.startswith("http"):
                imgs.append(src)

        return {
            "title":        title,
            "content":      content,
            "author":       "",
            "published_at": "",
            "top_image":    imgs[0] if imgs else "",
            "images":       imgs[:12],
            "summary":      content[:500],
        }
    except Exception:
        return None


def extract_with_playwright(url: str, browser_manager: BrowserContextManager) -> Optional[dict]:
    try:
        page = browser_manager.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=20000)
        time.sleep(2.5)
        
        title = page.title()
        
        content = ""
        for selector in ["article", "main", ".article-body", ".post-body", ".entry-content", ".story-detail", "body"]:
            el = page.query_selector(selector)
            if el:
                text = el.inner_text()
                if text and len(text.strip()) > 150:
                    content = text.strip()
                    break
                    
        images = []
        img_elements = page.query_selector_all("article img, main img, body img")
        for img in img_elements[:12]:
            src = img.get_attribute("src")
            if src and src.startswith("http") and not src.startswith("data:"):
                images.append(src)
                
        page.close()
        
        if len(content) < 80:
            return None
            
        return {
            "title":        title or "",
            "content":      content,
            "author":       "",
            "published_at": "",
            "top_image":    images[0] if images else "",
            "images":       images,
            "summary":      content[:500],
        }
    except Exception:
        return None


def make_rss_only_article(entry: dict, feed_name: str, feed_type: str, lang: str) -> dict:
    """
    When full article extraction fails, save what we have from the RSS entry itself.
    This gives us title, summary, link, and date at minimum.
    """
    title   = entry.get("title", "")
    summary = re.sub(r'<[^>]+>', '', entry.get("summary", ""))  # strip HTML
    content = f"{title}\n\n{summary}"

    # Try to get the source URL (for Google News entries, source.href is the publisher)
    source_url = ""
    if hasattr(entry, 'source') and hasattr(entry.source, 'href'):
        source_url = entry.source.href

    pub_date = ""
    if entry.get("published"):
        pub_date = entry["published"]
    elif entry.get("updated"):
        pub_date = entry["updated"]

    return {
        "title":        title,
        "content":      content,
        "author":       entry.get("author", ""),
        "published_at": pub_date,
        "top_image":    "",
        "images":       [],
        "summary":      summary[:500],
        "rss_only":     True,
    }


# ─── Image downloader ─────────────────────────────────────────────────────────────

def download_article_images(article_url: str, image_urls: list, session) -> list:
    img_dir = _image_dir(article_url)
    downloaded_images = []
    for i, img_url in enumerate(image_urls[:10]):
        if not img_url or not img_url.startswith("http"):
            continue
        local_path = os.path.join(img_dir, f"img_{i:02d}.jpg")
        if download_image(img_url, local_path, session=session):
            downloaded_images.append((img_url, local_path))
    return downloaded_images


def save_article_markdown(data: dict, out_dir: str):
    safe = _slug(data.get("title", "article"))
    filepath = os.path.join(out_dir, f"{safe}.md")
    try:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(f"# {data['title']}\n\n")
            f.write(f"> **Source:** {data['source_name']}  \n")
            f.write(f"> **URL:** <{data['url']}>  \n")
            f.write(f"> **Type:** {data['source_type']} | **Language:** {data['language']}  \n")
            if data.get('author'):
                f.write(f"> **Author:** {data['author']}  \n")
            if data.get('published_at'):
                f.write(f"> **Published:** {data['published_at']}  \n")
            if data.get('destination'):
                f.write(f"> **Destination:** {data['destination']}  \n")
            f.write("\n")
            if data.get("cover_image") and os.path.exists(data["cover_image"]):
                rel = os.path.relpath(data["cover_image"], out_dir).replace("\\", "/")
                f.write(f"![Cover]({rel})\n\n")
            f.write("---\n\n")
            f.write(data.get("content", ""))
            f.write(f"\n\n---\n*Crawled {datetime.now().strftime('%Y-%m-%d %H:%M')} | Bhromon Travel Crawler*\n")
    except Exception as e:
        print(f"    [Save Error] {e}", file=sys.stderr)


# ─── RSS Feed crawler ─────────────────────────────────────────────────────────────

def crawl_rss_feed(feed_config: dict, session: requests.Session, browser_manager: BrowserContextManager) -> int:
    name    = feed_config["name"]
    url     = feed_config["url"]
    stype   = feed_config.get("type", "news")
    lang    = feed_config.get("language", "en")
    out_dir = _article_dir(stype, name)
    saved   = 0
    skipped = 0
    failed  = 0

    print(f"\n  [{name}]")

    try:
        feed = feedparser.parse(url)
    except Exception as e:
        print(f"    RSS error: {e}")
        return 0

    if not feed.entries:
        print(f"    No RSS entries")
        return 0

    print(f"    {len(feed.entries)} entries in feed")

    for entry in feed.entries:
        raw_url = entry.get("link", "")
        if not raw_url:
            continue

        title_raw   = entry.get("title", "")
        summary_raw = re.sub(r'<[^>]+>', '', entry.get("summary", "") or entry.get("description", ""))
        combined    = title_raw + " " + summary_raw

        # Pre-filter on RSS entry metadata
        if not _is_travel_related(combined):
            skipped += 1
            continue

        # Resolve Google News redirect → actual article URL
        article_url = resolve_google_news_url(raw_url, browser_manager)
        if not article_url:
            article_url = raw_url

        if url_already_crawled(article_url):
            continue

        time.sleep(random.uniform(0.8, 2.0))

        # Try full extraction
        extracted = extract_with_newspaper(article_url)
        if not extracted:
            extracted = extract_with_bs4(article_url, session)
        if not extracted or len(extracted.get("content", "")) < 150:
            extracted_pw = extract_with_playwright(article_url, browser_manager)
            if extracted_pw:
                extracted = extracted_pw

        # Fall back to RSS-only data if extraction completely fails
        if not extracted or len(extracted.get("content", "")) < 60:
            # Only save RSS-only if it has a decent summary
            if len(summary_raw) > 80:
                extracted = make_rss_only_article(entry, name, stype, lang)
                extracted["content"] = summary_raw
                print(f"    → [RSS only] {title_raw[:70]}")
            else:
                log_crawl(name, article_url, "skip", "no content")
                failed += 1
                continue
        else:
            print(f"    → [Full] {(extracted.get('title') or title_raw)[:70]}")

        # Use RSS title if extraction got nothing
        title = extracted.get("title") or title_raw or article_url
        content = extracted["content"]

        # Download images
        all_imgs = extracted.get("images", [])
        if extracted.get("top_image") and extracted["top_image"] not in all_imgs:
            all_imgs.insert(0, extracted["top_image"])
        downloaded_images = download_article_images(article_url, all_imgs, session)
        local_images = [path for url, path in downloaded_images]
        cover_image  = local_images[0] if local_images else ""

        # Published date — prefer RSS feed date if extraction didn't find one
        pub_date = extracted.get("published_at") or entry.get("published") or entry.get("updated", "")

        # Final verification: does the extracted text actually contain keywords?
        # Use the same logic as _is_travel_related but return the matched keywords
        keywords = []
        full_text_lower = (title + " " + content).lower()
        for kw in TRAVEL_KEYWORDS:
            if len(kw) <= 5:
                if re.search(r'\b' + re.escape(kw.lower()) + r'\b', full_text_lower):
                    keywords.append(kw)
            else:
                if kw.lower() in full_text_lower:
                    keywords.append(kw)
                    
        if not keywords:
            print(f"    → [Skipped] Extracted content lost travel context: {title[:50]}")
            skipped += 1
            continue

        data = {
            "url":          article_url,
            "source_name":  name,
            "source_type":  stype,
            "language":     lang,
            "title":        title,
            "content":      content,
            "summary":      extracted.get("summary", content[:400]),
            "author":       extracted.get("author", ""),
            "published_at": pub_date,
            "keywords":     keywords,
            "images":       local_images,
            "cover_image":  cover_image,
            "word_count":   len(content.split()),
            "destination":  _detect_destination(title + " " + content[:600]),
        }

        try:
            # Filter out obvious non-article junk pages like google news homepage
            if "news.google.com/home" in article_url or len(content.split()) < 50:
                print(f"    → [Skipped] Invalid article content/URL")
                skipped += 1
                continue
                
            article_id = save_article(data)
            save_article_markdown(data, out_dir)
            for img_url, img_path in downloaded_images:
                save_image(article_id, img_url, img_path)
            log_crawl(name, article_url, "ok")
            saved += 1
        except Exception as e:
            log_crawl(name, article_url, "error", str(e))
            failed += 1

    print(f"    Done: {saved} saved, {skipped} non-travel skipped, {failed} failed")
    return saved


def crawl_all_articles() -> int:
    session = make_session()
    total = 0
    print(f"\n[RSS CRAWLER] Processing {len(RSS_FEEDS)} feeds...")
    
    with BrowserContextManager() as browser_manager:
        for feed_config in RSS_FEEDS:
            try:
                total += crawl_rss_feed(feed_config, session, browser_manager)
            except Exception as e:
                print(f"    [Feed Error] {feed_config['name']}: {e}")
                
    print(f"\n[RSS CRAWLER] Complete. Total: {total} articles")
    return total


def crawl_all_news() -> int:
    return crawl_all_articles()

def crawl_all_blogs() -> int:
    return 0
