from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Let's search for elements that have common class names of post body text
# Usually, Comet post text is inside a div with classes like 'xdj266r' and 'x11i5rnm' and 'xat24cr'
# Let's find divs that have 'xdj266r' and 'x11i5rnm' or similar

print("--- Searching for divs with xdj266r and x11i5rnm ---")
text_divs = soup.find_all("div", class_=lambda c: c and 'xdj266r' in c and 'x11i5rnm' in c)
# If that's empty, let's look for divs containing 'xdj266r'
if not text_divs:
    print("No divs with both, searching for xdj266r only...")
    text_divs = soup.find_all("div", class_=lambda c: c and 'xdj266r' in c)

print(f"Found {len(text_divs)} divs.")

seen_texts = set()
for i, d in enumerate(text_divs):
    text = d.get_text(separator="\n", strip=True)
    if not text or len(text) < 30:
        continue
    
    # Avoid duplicates
    clean_txt = " ".join(text.split())
    if clean_txt in seen_texts:
        continue
    seen_texts.add(clean_txt)
    
    print(f"\n[{i}] Class: {d.get('class')} | Length: {len(text)}")
    print(text[:400])
    print("-" * 50)
