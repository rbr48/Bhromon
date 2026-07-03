"""
Bhromon Travel Crawler — Facebook public page scraper.
Uses Playwright to scroll and render dynamic posts.
Handles Facebook Comet UI layout and DOM virtualization.
"""
import os
import re
import hashlib
import time
from typing import Optional

from bs4 import BeautifulSoup
import requests

from config import FACEBOOK_PAGES, FACEBOOK_DIR, IMAGES_DIR, FACEBOOK_COOKIES_FILE, TRAVEL_KEYWORDS
from browser_utils import BrowserContextManager
from database import save_facebook_post, log_crawl

def _is_travel_related(text: str) -> bool:
    return any(kw.lower() in text.lower() for kw in TRAVEL_KEYWORDS)

def _image_dir_for_post(post_id: str) -> str:
    d = os.path.join(IMAGES_DIR, "facebook", post_id[:8])
    os.makedirs(d, exist_ok=True)
    return d

def _clean_post_text(text: str) -> str:
    # Remove lines containing Facebook interface elements
    lines = text.split("\n")
    cleaned_lines = []
    for line in lines:
        line_strip = line.strip()
        if not line_strip:
            continue
        # Skip common UI terms
        if line_strip in ["Facebook", "Like", "Comment", "Share", "Send", "Reply", "Write a comment...", "See more", "See translation", "Log in", "Sign up", "Featured"]:
            continue
        # Skip single chars or numbers
        if len(line_strip) <= 2 and line_strip.isdigit():
            continue
        cleaned_lines.append(line_strip)
    return "\n".join(cleaned_lines)

def _extract_posts_from_html(html: str, page_name: str) -> list:
    """Parse posts from dynamic Facebook HTML using a highly resilient hybrid card strategy."""
    soup = BeautifulSoup(html, "lxml")
    posts = []
    
    # Collect candidates from multiple possible card wrappers
    candidates = []
    
    # 1. Comet Card wrapper
    for card in soup.find_all("div", class_="x1yztbdb"):
        candidates.append(card)
        
    # 2. Comet Feed item wrapper
    for card in soup.find_all("div", class_="x1a2a7pz"):
        candidates.append(card)
        
    # 3. Standard article role
    for card in soup.find_all("div", role="article"):
        candidates.append(card)
        
    # 4. Posinset feed items
    for card in soup.find_all("div", attrs={"aria-posinset": True}):
        candidates.append(card)

    seen_sigs = set()

    for card in candidates:
        # Try to find specific text body containers first to get clean text
        message_div = card.find("div", attrs={"data-ad-preview": "message"}) or card.find("div", attrs={"data-ad-comet-preview": "message"})
        
        post_text = ""
        if message_div:
            post_text = message_div.get_text(separator="\n", strip=True)
        else:
            # Look for colored background text
            colored_div = card.find("div", class_=lambda c: c and 'x1yx25j4' in c)
            if colored_div:
                post_text = colored_div.get_text(separator="\n", strip=True)
            else:
                # Fallback to cleaning the entire card text
                card_text = card.get_text(separator="\n", strip=True)
                post_text = _clean_post_text(card_text)
                
        if not post_text or len(post_text) < 40:
            continue
            
        # De-duplicate
        sig = " ".join(post_text.split())[:120]
        if sig in seen_sigs:
            continue
        seen_sigs.add(sig)

        # Extract images
        images = []
        for img in card.find_all("img"):
            src = img.get("src", "")
            if src and "scontent" in src and "emoji" not in src:
                images.append(src)

        # Extract links
        links = []
        for a in card.find_all("a", href=True):
            href = a.get("href", "")
            if href.startswith("http") and "facebook.com" not in href: # Prefer external links
                links.append(href)
            elif href.startswith("http") and ("posts/" in href or "fbid=" in href):
                links.append(href)
        # De-duplicate links
        links = list(set(links))
        
        post_id = hashlib.md5((page_name + post_text[:50]).encode()).hexdigest()[:12]
        
        posts.append({
            "post_id":   post_id,
            "page":      page_name,
            "content":   post_text[:2000],
            "post_date": "",
            "likes":     0,
            "comments":  0,
            "shares":    0,
            "images":    images,
            "links":     links,
        })
        
    return posts

def crawl_facebook_page(url: str, browser_manager: BrowserContextManager) -> int:
    page_name = url.rstrip("/").split("/")[-1]
    
    out_dir = os.path.join(FACEBOOK_DIR, page_name)
    os.makedirs(out_dir, exist_ok=True)
    
    print(f"\n[FACEBOOK] Crawling: {url}")
    saved = 0
    
    try:
        page = browser_manager.new_page()
        page.goto(url, wait_until="networkidle", timeout=30000)
        
        # Scroll and accumulate posts to handle Comet UI virtualization
        all_posts = []
        seen_sigs = set()
        
        print("    Scrolling and collecting posts...")
        for scroll_step in range(25):
            # Scroll down by a moderate amount to trigger dynamic loading
            page.evaluate("window.scrollBy(0, 1200)")
            # Wait for content to render and trigger lazy loading
            time.sleep(2.5)
            
            html = page.content()
            step_posts = _extract_posts_from_html(html, page_name)
            
            new_in_step = 0
            for post in step_posts:
                sig = " ".join(post["content"].split())[:120]
                if sig and sig not in seen_sigs:
                    seen_sigs.add(sig)
                    all_posts.append(post)
                    new_in_step += 1
            
        page.close()
        
        print(f"    Total unique posts extracted: {len(all_posts)}")
        
        # Filter and save travel-related posts
        for post in all_posts:
            if not _is_travel_related(post["content"]):
                continue
                
            local_images = []
            img_dir = _image_dir_for_post(post["post_id"])
            for i, img_url in enumerate(post["images"][:8]):
                ext = ".jpg"
                local_path = os.path.join(img_dir, f"fb_{post['post_id']}_{i}{ext}")
                try:
                    r = requests.get(img_url, timeout=10)
                    if r.status_code == 200:
                        with open(local_path, "wb") as f:
                            f.write(r.content)
                        local_images.append(local_path)
                except Exception:
                    pass
                    
            post["images"] = local_images

            filepath = os.path.join(out_dir, f"{post['post_id']}.txt")
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(f"Page: {post['page']}\n")
                f.write(f"Date: {post['post_date']}\n")
                f.write(f"Images: {len(local_images)}\n\n")
                f.write(post["content"] + "\n")
            
            save_facebook_post(post)
            log_crawl("facebook", f"{url}/{post['post_id']}", "ok", f"Saved post from {page_name}")
            saved += 1
            
        print(f"    Saved {saved} travel-related posts to database.")
            
    except Exception as e:
        print(f"    [FB Error] {e}")
        log_crawl("facebook", url, "error", str(e))
            
    return saved

def crawl_all_facebook() -> int:
    if not os.path.exists(FACEBOOK_COOKIES_FILE):
        print("[Facebook] Skipping Facebook crawl — no cookies provided.")
        return 0

    total = 0
    with BrowserContextManager() as browser_manager:
        if not browser_manager.load_cookies(FACEBOOK_COOKIES_FILE):
            print("[Facebook] Warning: Failed to load cookies properly, continuing anyway.")
            
        for page_url in FACEBOOK_PAGES:
            total += crawl_facebook_page(page_url, browser_manager)

    print(f"\n[FACEBOOK] Done. Total posts saved: {total}")
    return total

