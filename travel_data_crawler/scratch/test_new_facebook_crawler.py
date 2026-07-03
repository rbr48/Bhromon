import os
import sys

# Setup paths
sys.path.insert(0, os.getcwd())

from browser_utils import BrowserContextManager
from facebook_crawler import crawl_facebook_page
from config import FACEBOOK_COOKIES_FILE

def test():
    if not os.path.exists(FACEBOOK_COOKIES_FILE):
        print(f"Cookie file not found at {FACEBOOK_COOKIES_FILE}")
        return
        
    print("Starting test crawl on TravelBangladesh...")
    with BrowserContextManager() as browser_manager:
        browser_manager.load_cookies(FACEBOOK_COOKIES_FILE)
        # Crawl only TravelBangladesh for testing
        saved = crawl_facebook_page("https://www.facebook.com/TravelBangladesh", browser_manager)
        print(f"\nSaved {saved} posts in test.")

if __name__ == "__main__":
    test()
