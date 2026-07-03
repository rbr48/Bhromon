from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

target_text = "সশরীরে রাজপথে"
elements = [tag for tag in soup.find_all(True) if tag.get_text() and target_text in tag.get_text()]
el = min(elements, key=lambda t: len(t.get_text()))

parent = el.parent
depth = 0
while parent:
    classes = parent.get('class', [])
    if 'x1yztbdb' in classes:
        print(f"Parent at Depth {depth} has class x1yztbdb!")
        print(f"Parent tag: {parent.name}")
        print(f"Parent classes: {classes}")
        # Let's get the text of this parent node directly using BS
        p_text = parent.get_text(separator=" ", strip=True)
        print(f"Parent text len: {len(p_text)}")
        print(f"Parent text snippet: {p_text[:300]}")
        
        # Check if this parent is in soup.find_all("div", class_="x1yztbdb")
        all_yzt = soup.find_all("div", class_="x1yztbdb")
        if parent in all_yzt:
            idx = all_yzt.index(parent)
            print(f"Yes! This parent is in the list at index {idx}!")
        else:
            print("No! This parent is NOT in the find_all list!")
            
    parent = parent.parent
    depth += 1
