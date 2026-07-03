from bs4 import BeautifulSoup
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")
post_containers = soup.find_all("div", attrs={"aria-posinset": True})

print(f"Found {len(post_containers)} post containers with aria-posinset.")

for i, container in enumerate(post_containers):
    pos = container.get("aria-posinset")
    text = container.get_text(separator=" ", strip=True)
    
    # Facebook lazy-loads some off-screen posts, they might only have "Facebook" or be empty.
    # Let's see what is inside each one.
    print(f"\n[{i}] Position {pos} (text length={len(text)}):")
    
    # Try to find the actual post text (often inside dir="auto" div/span that has the body text)
    # We can clean up the text extraction to avoid header/footer noise or print the whole thing
    print(text[:400])
    
    # Find images
    images = []
    for img in container.find_all("img"):
        src = img.get("src", "")
        if src and "scontent" in src and "emoji" not in src:
            images.append(src)
    print(f"    Images count: {len(images)}")
