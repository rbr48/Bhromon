import os
import sys
from bs4 import BeautifulSoup

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

target_text = "বান্দরবান জেলা সদর থেকে"
elements = [tag for tag in soup.find_all(True) if tag.get_text() and target_text in tag.get_text()]

if not elements:
    print("Nilgiri text not found")
    sys.exit(0)

# Get the deepest element containing the text
deepest_el = min(elements, key=lambda t: len(t.get_text()))
print(f"Deepest element: {deepest_el.name} | Classes: {deepest_el.get('class')}")

parent = deepest_el.parent
depth = 0
while parent:
    role = parent.get('role')
    data_testid = parent.get('data-testid')
    classes = parent.get('class')
    id_val = parent.get('id')
    print(f"Depth {depth}: <{parent.name}> | ID: {id_val} | Role: {role} | TestID: {data_testid} | Classes: {classes}")
    parent = parent.parent
    depth += 1
