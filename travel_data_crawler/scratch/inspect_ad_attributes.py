from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Search for common data-ad attributes
for attr in ["data-ad-preview", "data-ad-comet-preview", "data-testid"]:
    elms = soup.find_all(lambda tag: tag.has_attr(attr))
    print(f"Found {len(elms)} elements with attribute: {attr}")
    for i, el in enumerate(elms[:3]):
        print(f"  [{i}] tag: {el.name} | val: {el.get(attr)} | text snippet: {el.get_text()[:100]}")
