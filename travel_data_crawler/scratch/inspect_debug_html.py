from bs4 import BeautifulSoup
import os

def inspect_structure(filepath):
    if not os.path.exists(filepath):
        print(f"{filepath} does not exist.")
        return
    with open(filepath, "r", encoding="utf-8") as f:
        html = f.read()
    
    soup = BeautifulSoup(html, "html.parser")
    print(f"\nStructure for: {filepath}")
    print(f"Title: {soup.title.string if soup.title else 'No Title'}")
    print(f"Total divs: {len(soup.find_all('div'))}")
    
    # Print some divs with classes, or text snippets
    text = soup.get_text()
    print(f"Text length: {len(text)}")
    print(f"Sample text: {text[:400]}")
    
    # Look for common selectors or potential posts
    # For example, look for something containing "posts" or class names
    print("Potential class names of divs (first 10 unique):")
    classes = set()
    for d in soup.find_all('div'):
        c = d.get('class')
        if c:
            classes.add(" ".join(c))
    print(list(classes)[:10])

inspect_structure("fb_debug.html")
inspect_structure("fb_mbasic_debug.html")
inspect_structure("fb_www_debug.html")
