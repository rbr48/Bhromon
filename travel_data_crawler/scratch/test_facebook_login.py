import os
import json
import time
from playwright.sync_api import sync_playwright

COOKIE_FILE = r"e:\Projects\Bhromon\travel_data_crawler\cookies\facebook_cookies.json"
TEST_URL = "https://www.facebook.com/TravelBangladesh"
SCREENSHOT_PATH = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_screenshot.png"
HTML_PATH = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"

def test_crawl():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # Try custom context
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1280, 'height': 800}
        )
        
        # Load cookies
        if os.path.exists(COOKIE_FILE):
            with open(COOKIE_FILE, "r", encoding="utf-8") as f:
                raw_cookies = json.load(f)
            formatted_cookies = []
            if isinstance(raw_cookies, list):
                for c in raw_cookies:
                    if "name" in c and "value" in c:
                        formatted_cookies.append({
                            "name": c["name"],
                            "value": str(c["value"]),
                            "domain": c.get("domain", ".facebook.com"),
                            "path": c.get("path", "/")
                        })
            if formatted_cookies:
                context.add_cookies(formatted_cookies)
                print(f"Loaded {len(formatted_cookies)} cookies.")
            else:
                print("No cookies found to load.")
        
        page = context.new_page()
        print(f"Navigating to {TEST_URL}...")
        page.goto(TEST_URL, wait_until="networkidle", timeout=30000)
        
        # Scroll and wait to let it load
        print("Scrolling...")
        for i in range(3):
            page.evaluate("window.scrollBy(0, document.body.scrollHeight)")
            time.sleep(3)
            
        print("Taking screenshot...")
        page.screenshot(path=SCREENSHOT_PATH)
        
        print("Saving HTML...")
        with open(HTML_PATH, "w", encoding="utf-8") as f:
            f.write(page.content())
            
        print("Done! Check screenshot and HTML.")
        browser.close()

if __name__ == "__main__":
    test_crawl()
