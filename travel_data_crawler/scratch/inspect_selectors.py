import os
import sys
from bs4 import BeautifulSoup

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Search for the specific Bengali text from the screenshot
target_text = "সশরীরে রাজপথে"

print("Searching for target text...")
elements = soup.find_all(lambda tag: tag.string and target_text in tag.string)
if not elements:
    # Try finding in tag text (separator=...)
    elements = [tag for tag in soup.find_all(True) if tag.get_text() and target_text in tag.get_text()]

print(f"Found {len(elements)} elements containing target text.")
for i, el in enumerate(elements[:5]):
    print(f"\n--- Element {i} ---")
    print(f"Tag: {el.name}")
    print(f"Classes: {el.get('class')}")
    print(f"Attributes: {el.attrs}")
    print(f"Text snippet: {el.get_text()[:200]}")
    
    # Trace parents
    print("Parent trace:")
    parent = el.parent
    depth = 0
    while parent and depth < 6:
        print(f"  Parent {depth}: {parent.name} | Classes: {parent.get('class')} | Role: {parent.get('role')} | Attributes: {list(parent.attrs.keys())}")
        parent = parent.parent
        depth += 1
