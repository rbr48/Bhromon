from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")
divs = soup.find_all("div", class_="x1yztbdb")
print(f"Total divs with class 'x1yztbdb': {len(divs)}")

for i, div in enumerate(divs):
    text = div.get_text(separator="\n", strip=True)
    print(f"\n[{i}] Text len={len(text)}:")
    print(text[:300])
    
    # Extract images inside this div
    images = []
    for img in div.find_all("img"):
        src = img.get("src", "")
        if src and "scontent" in src and "emoji" not in src:
            images.append(src)
    print(f"    Images count: {len(images)}")
