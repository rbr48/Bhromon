from bs4 import BeautifulSoup
import os
import sys
import re

sys.stdout.reconfigure(encoding='utf-8')

filepath = r"e:\Projects\Bhromon\travel_data_crawler\scratch\fb_test_page.html"
with open(filepath, "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

# Find all post cards
cards = soup.find_all("div", class_="x1yztbdb")
print(f"Found {len(cards)} post cards with class 'x1yztbdb'.")

def clean_post_text(text):
    # Remove lines containing Facebook interface elements
    lines = text.split("\n")
    cleaned_lines = []
    for line in lines:
        line_strip = line.strip()
        if not line_strip:
            continue
        # Skip common UI terms
        if line_strip in ["Facebook", "Like", "Comment", "Share", "Send", "Reply", "Write a comment...", "See more", "See translation"]:
            continue
        # Skip single chars or numbers
        if len(line_strip) <= 2 and line_strip.isdigit():
            continue
        cleaned_lines.append(line_strip)
    return "\n".join(cleaned_lines)

extracted_count = 0
for i, card in enumerate(cards):
    # Try to get post text
    # Method A: Look for data-ad-preview="message"
    message_div = card.find("div", attrs={"data-ad-preview": "message"}) or card.find("div", attrs={"data-ad-comet-preview": "message"})
    
    post_text = ""
    if message_div:
        post_text = message_div.get_text(separator="\n", strip=True)
    else:
        # Method B: Look for colored background text style
        colored_div = card.find("div", class_=lambda c: c and 'x1yx25j4' in c)
        if colored_div:
            post_text = colored_div.get_text(separator="\n", strip=True)
        else:
            # Method C: Fallback to cleaning the whole card text
            card_text = card.get_text(separator="\n", strip=True)
            post_text = clean_post_text(card_text)
            
    if not post_text or len(post_text) < 30:
        continue
        
    # Extract images
    images = []
    for img in card.find_all("img"):
        src = img.get("src", "")
        if src and "scontent" in src and "emoji" not in src:
            images.append(src)
            
    # Extract links
    links = [a.get("href", "") for a in card.find_all("a", href=True) if a.get("href", "").startswith("http")]
    
    # Check if we've already extracted this text (de-duplicate)
    print(f"\nCard [{i}] Extracted Post:")
    print(f"Text Snippet: {post_text[:300]}")
    print(f"Images count: {len(images)}")
    print(f"Links count: {len(links)}")
    extracted_count += 1

print(f"\nTotal extracted: {extracted_count}")
