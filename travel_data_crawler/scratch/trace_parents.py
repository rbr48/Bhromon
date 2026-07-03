import os
import sys
from bs4 import BeautifulSoup

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

target_text = "সশরীরে রাজপথে"
elements = [tag for tag in soup.find_all(True) if tag.get_text() and target_text in tag.get_text()]

if not elements:
    print("Text not found")
    sys.exit(0)

# Find the deepest element that contains the text
deepest_el = None
for tag in soup.find_all(True):
    if tag.string and target_text in tag.string:
        deepest_el = tag
        break
if not deepest_el:
    # Fallback to get_text() but find the one with the smallest text length
    candidates = [tag for tag in soup.find_all(True) if tag.get_text() and target_text in tag.get_text()]
    if candidates:
        deepest_el = min(candidates, key=lambda t: len(t.get_text()))

if not deepest_el:
    print("Text not found")
    sys.exit(0)

el = deepest_el
print(f"Found element: {el.name} with classes: {el.get('class')}")
print(f"Content: {el.get_text()[:100]}")

parent = el.parent
depth = 0
while parent:
    role = parent.get('role')
    data_testid = parent.get('data-testid')
    classes = parent.get('class')
    id_val = parent.get('id')
    # Print it
    print(f"Depth {depth}: <{parent.name}> | ID: {id_val} | Role: {role} | TestID: {data_testid} | Classes: {classes}")
    parent = parent.parent
    depth += 1
