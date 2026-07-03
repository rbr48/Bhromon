import os
import json
from playwright.sync_api import sync_playwright

class BrowserContextManager:
    def __init__(self):
        self.playwright = None
        self.browser = None
        self.context = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()

    def start(self, headless=True):
        self.playwright = sync_playwright().start()
        self.browser = self.playwright.chromium.launch(headless=headless)
        self.context = self.browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1280, 'height': 800}
        )
        # Block unnecessary resources to speed up crawling
        self.context.route("**/*", self._route_interceptor)
        
    def _route_interceptor(self, route):
        # We need html and images. We can block media, fonts. 
        # Don't block JS since we need Playwright precisely to render JS.
        if route.request.resource_type in ["media", "font"]:
            route.abort()
        else:
            route.continue_()

    def load_cookies(self, cookie_file):
        if not os.path.exists(cookie_file):
            return False
            
        try:
            with open(cookie_file, "r", encoding="utf-8") as f:
                raw_cookies = json.load(f)
                
            formatted_cookies = []
            
            # If cookies are in name:value dict format (like we previously parsed)
            if isinstance(raw_cookies, dict):
                for name, value in raw_cookies.items():
                    formatted_cookies.append({
                        "name": name,
                        "value": str(value),
                        "domain": ".facebook.com",
                        "path": "/"
                    })
            # If cookies are already in standard list of dicts format
            elif isinstance(raw_cookies, list):
                for c in raw_cookies:
                    if "name" in c and "value" in c:
                        # Ensure required fields for playwright
                        c_dict = {
                            "name": c["name"],
                            "value": str(c["value"]),
                            "domain": c.get("domain", ".facebook.com"),
                            "path": c.get("path", "/")
                        }
                        formatted_cookies.append(c_dict)
                        
            if formatted_cookies:
                self.context.add_cookies(formatted_cookies)
                return True
        except Exception as e:
            print(f"[Browser] Error loading cookies: {e}")
            
        return False

    def new_page(self):
        return self.context.new_page()

    def stop(self):
        if self.context:
            self.context.close()
        if self.browser:
            self.browser.close()
        if self.playwright:
            self.playwright.stop()
