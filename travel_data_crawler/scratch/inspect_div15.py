from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")
divs = soup.find_all("div", class_="x1yztbdb")

for i in [1, 15, 16, 17]:
    if i < len(divs):
        print(f"\n=====================================")
        print(f"Div [{i}] HTML snippet (first 1500 chars):")
        print(str(divs[i])[:1500])
