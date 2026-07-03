import os
import sys
from bs4 import BeautifulSoup

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Let's inspect some of the classes we saw in the parent chain
# Depth 14: 'x1a2a7pz'
# Depth 18: 'x1yztbdb'
# Depth 22: 'xeuugli', 'xs83m0k', 'xjl7jj' ...
# Depth 23: 'x2lah0s', 'x1qjc9v5' ...

classes_to_check = ['x1a2a7pz', 'x1yztbdb', 'x2lah0s', 'xeuugli']

for cls in classes_to_check:
    divs = soup.find_all("div", class_=cls)
    print(f"\nClass: {cls} -> Found {len(divs)} divs")
    for i, d in enumerate(divs[:5]):
        txt = d.get_text(separator=" ", strip=True)
        print(f"  [{i}] Text len={len(txt)}: {txt[:150]}")

# Let's search for "See more" or "See translation" which are very common in posts
print("\n--- Searching for 'See more' or dynamic post elements ---")
for btn in soup.find_all(True):
    txt = btn.get_text()
    if "See more" in txt or "August 3, 2024" in txt:
        print(f"Tag: {btn.name} | Class: {btn.get('class')} | Snippet: {txt[:100]}")
