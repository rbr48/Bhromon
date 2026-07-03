from bs4 import BeautifulSoup
import os
import sys

# Reconfigure stdout to use utf-8
sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
if not os.path.exists(filepath):
    print("File not found")
    sys.exit(1)

with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")
articles = soup.find_all("div", role="article")
print(f"Total role='article' divs in test html: {len(articles)}")

for i, art in enumerate(articles):
    text = art.get_text(separator=" ", strip=True)
    print(f"\n[{i}] Text (len={len(text)}):")
    print(text[:300])
    
    # Check if contains any travel keywords
    from config import TRAVEL_KEYWORDS
    matched_kws = [kw for kw in TRAVEL_KEYWORDS if kw.lower() in text.lower()]
    print(f"    Matched keywords: {matched_kws}")
