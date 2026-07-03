import os
import sys
from bs4 import BeautifulSoup

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Let's find all divs that might represent posts
# In modern FB, posts are usually inside divs that contain the text of the post and some metadata.
# Let's find all divs with class `html-div` and some common post characteristics,
# or simply find all text blocks that are long enough and see what they are.

# Let's extract all text blocks that contain common post indicators (like date, Like, Reply, Share, See more)
# or let's use the selectors to extract unique post contents.
# A post message is often inside a div with dir="auto" or class containing post text styles.
# Let's search for divs with dir="auto"
divs_dir_auto = soup.find_all("div", dir="auto")
print(f"Found {len(divs_dir_auto)} divs with dir='auto'")

seen_texts = set()
posts_extracted = []

for d in divs_dir_auto:
    text = d.get_text(separator=" ", strip=True)
    if not text or len(text) < 30:
        continue
    # Let's avoid duplicates
    if text in seen_texts:
        continue
    seen_texts.add(text)
    
    # Check if this text seems to be a post body (usually has no 'Like', 'Reply', etc inside it, or is a paragraph)
    # Let's just print it to see
    posts_extracted.append(text)

print(f"\n--- Extracted {len(posts_extracted)} unique text blocks (len >= 30) ---")
for i, p in enumerate(posts_extracted):
    print(f"\nPost [{i}]:")
    print(p[:400])
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sys.path.insert(0, os.getcwd())
    from config import TRAVEL_KEYWORDS
    matched_kws = [kw for kw in TRAVEL_KEYWORDS if kw.lower() in p.lower()]
    print(f"Matched Keywords: {matched_kws}")

