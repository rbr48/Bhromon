from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

def clean_text(text):
    return " ".join(text.split())

# We will try multiple selectors
candidates = []

# 1. role="article"
for el in soup.find_all("div", role="article"):
    candidates.append(el)

# 2. x1yztbdb
for el in soup.find_all("div", class_="x1yztbdb"):
    candidates.append(el)

# 3. x1a2a7pz
for el in soup.find_all("div", class_="x1a2a7pz"):
    candidates.append(el)

# 4. divs with aria-posinset
for el in soup.find_all("div", attrs={"aria-posinset": True}):
    candidates.append(el)

print(f"Total raw candidates: {len(candidates)}")

unique_posts = []
seen_texts = set()

for el in candidates:
    text = el.get_text(separator="\n", strip=True)
    if not text or len(text) < 40:
        continue
    
    # Let's clean the text to use as a signature
    sig = clean_text(text[:100])
    if sig in seen_texts:
        continue
    seen_texts.add(sig)
    
    # Extract images
    images = []
    for img in el.find_all("img"):
        src = img.get("src", "")
        if src and "scontent" in src and "emoji" not in src:
            images.append(src)
            
    unique_posts.append({
        "text": text,
        "images": images
    })

print(f"\n--- Extracted {len(unique_posts)} unique posts ---")
for i, p in enumerate(unique_posts):
    print(f"\n[{i}] Text length={len(p['text'])} | Images count={len(p['images'])}")
    print(p['text'][:300])
    print("-" * 40)
