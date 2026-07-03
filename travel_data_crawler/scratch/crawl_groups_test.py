import os
import json
import time
import sys
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

COOKIE_FILE = r"E:\Projects\Bhromon\travel_data_crawler\cookies\facebook_cookies.json"
GROUPS = [
    "https://www.facebook.com/groups/mail.tob",
    "https://www.facebook.com/groups/647450768707652"
]

def clean_text(text):
    lines = text.split("\n")
    cleaned = []
    for line in lines:
        l = line.strip()
        if not l:
            continue
        if l in ["Facebook", "Like", "Comment", "Share", "Send", "Reply", "Write a comment...", "See more", "See translation", "Log in", "Sign up", "Featured", "Public group", "Join Group", "About", "Discussion"]:
            continue
        cleaned.append(l)
    return "\n".join(cleaned)

def test_crawl_groups():
    if not os.path.exists(COOKIE_FILE):
        print("Cookies file not found.")
        return

    with open(COOKIE_FILE, "r", encoding="utf-8") as f:
        cookies = json.load(f)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1280, 'height': 800}
        )
        
        # Load cookies
        formatted = []
        for c in cookies:
            formatted.append({
                "name": c["name"],
                "value": str(c["value"]),
                "domain": c.get("domain", ".facebook.com"),
                "path": c.get("path", "/")
            })
        context.add_cookies(formatted)
        
        for group_url in GROUPS:
            print(f"\nCrawling group: {group_url}")
            page = context.new_page()
            page.goto(group_url, wait_until="domcontentloaded", timeout=30000)
            page.wait_for_timeout(5000)
            
            # Scroll a few times
            print("Scrolling group page...")
            for _ in range(5):
                page.evaluate("window.scrollBy(0, 1000)")
                time.sleep(2.5)
                
            html = page.content()
            soup = BeautifulSoup(html, "lxml")
            
            # Find articles/posts
            cards = soup.find_all("div", attrs={"role": "article"})
            print(f"Found {len(cards)} role='article' containers.")
            
            count = 0
            for card in cards:
                # Find message
                msg_div = card.find("div", attrs={"data-ad-preview": "message"}) or card.find("div", attrs={"data-ad-comet-preview": "message"})
                if msg_div:
                    text = msg_div.get_text(separator="\n", strip=True)
                else:
                    text = clean_text(card.get_text(separator="\n", strip=True))
                    
                if not text or len(text) < 100:
                    continue
                    
                # Find images
                images = []
                for img in card.find_all("img"):
                    src = img.get("src", "")
                    if src and "scontent" in src and "emoji" not in src:
                        images.append(src)
                        
                print(f"\n--- Post {count+1} ({len(text)} chars, {len(images)} images) ---")
                print(text[:300] + "...")
                print("Images:", images[:2])
                count += 1
                if count >= 3:
                    break
            
            page.close()
        browser.close()

if __name__ == "__main__":
    test_crawl_groups()
