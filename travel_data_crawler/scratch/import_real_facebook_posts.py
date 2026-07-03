import os
import json
import time
import sys
import re
import hashlib
import requests
import urllib.request
import urllib.parse
from datetime import datetime
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

# Try to import firebase client libraries
try:
    from google.cloud import firestore
    import google.oauth2.credentials
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "google-cloud-firestore"])
    from google.cloud import firestore
    import google.oauth2.credentials

# Force UTF-8 stdout for printing Bengali text to Windows terminal
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

# Configurations
COOKIE_FILE = r"E:\Projects\Bhromon\travel_data_crawler\cookies\facebook_cookies.json"
PROJECT_ID = "bhromon-ff801"
AUTHOR_UID = "travelers_of_bangladesh"

# Search targets for the remaining destinations in the app
SEARCH_TARGETS = [
    {"query": "বান্দরবান", "pin_id": "pin_bandarban", "district": "Bandarban", "division": "Chittagong"},
    {"query": "সেন্টমার্টিন", "pin_id": "pin_saintmartin", "district": "Cox's Bazar", "division": "Chittagong"},
    {"query": "রাতারগুল", "pin_id": "pin_ratargul", "district": "Sylhet", "division": "Sylhet"},
    {"query": "শ্রীমঙ্গল", "pin_id": "pin_sreemangal", "district": "Moulvibazar", "division": "Sylhet"},
    {"query": "সুন্দরবন", "pin_id": "pin_sundarbans", "district": "Khulna", "division": "Khulna"},
    {"query": "লালবাগ কেল্লা", "pin_id": "pin_lalbagh", "district": "Dhaka", "division": "Dhaka"},
    {"query": "আহসান মঞ্জিল", "pin_id": "pin_ahsanmanzil", "district": "Dhaka", "division": "Dhaka"},
    {"query": "ষাট গম্বুজ", "pin_id": "pin_shatgombuj", "district": "Bagerhat", "division": "Khulna"}
]

# We will search this group primarily as it has the highest quality photo posts
SEARCH_GROUP = "https://www.facebook.com/groups/mail.tob"

UI_TERMS = {
    "facebook", "like", "comment", "share", "send", "reply", "write a comment...",
    "see more", "see translation", "log in", "sign up", "featured", "public group",
    "join group", "about", "discussion", "joined", "invitation", "members", "admin",
    "moderator", "top contributor", "suggested for you", "write something...",
    "active", "photo/video", "anonymous member", "anonymous", "people", "events",
    "media", "files", "reels", "search"
}

def clean_paragraph(p_text):
    p_text = p_text.strip()
    if not p_text:
        return ""
    p_lower = p_text.lower()
    if p_lower in UI_TERMS:
        return ""
    if any(p_lower.startswith(term) for term in ["like", "comment", "share", "reply", "write a"]):
        return ""
    if re.match(r'^\d+[mhdwy]$', p_text) or p_text in ["Sponsored", "Edited", "Just now"]:
        return ""
    return p_text

def clean_post_text(raw_text):
    lines = raw_text.split("\n")
    cleaned = []
    for line in lines:
        cleaned_line = clean_paragraph(line)
        if cleaned_line:
            cleaned.append(cleaned_line)
    return "\n".join(cleaned)

def get_refresh_token():
    path = os.path.expanduser("~/.config/configstore/firebase-tools.json")
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        return data["tokens"]["refresh_token"]

def get_fresh_access_token():
    refresh_token = get_refresh_token()
    url = "https://oauth2.googleapis.com/token"
    client_id = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
    client_secret = "j9iVZfS8kkCEFUPaAeJV0sAi"
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token"
    }
    req_data = urllib.parse.urlencode(data).encode('utf-8')
    req = urllib.request.Request(url, data=req_data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())["access_token"]

def generate_cost_items(pin_id):
    if pin_id == "pin_sajek":
        return [
            {"category": "Transport (Bus & Jeep)", "amountBDT": 2200},
            {"category": "Resort Accommodation", "amountBDT": 3000},
            {"category": "Food (Bamboo Chicken)", "amountBDT": 1200},
            {"category": "Local Guides & Entry", "amountBDT": 200}
        ]
    elif pin_id == "pin_saintmartin":
        return [
            {"category": "Transport (Bus & Ship)", "amountBDT": 2400},
            {"category": "Hotel Stay (Saint Martin)", "amountBDT": 2500},
            {"category": "Food (Fresh Seafood)", "amountBDT": 1500},
            {"category": "Cycle Rent & Activities", "amountBDT": 300}
        ]
    elif pin_id == "pin_bandarban":
        return [
            {"category": "Transport (Bus & Jeep)", "amountBDT": 1800},
            {"category": "Hotel Stay (Bandarban)", "amountBDT": 2000},
            {"category": "Food & Meals", "amountBDT": 1000},
            {"category": "Local Guide & Treks", "amountBDT": 500}
        ]
    elif pin_id == "pin_sreemangal":
        return [
            {"category": "Transport (Train/Bus)", "amountBDT": 700},
            {"category": "Resort / Hotel Stay", "amountBDT": 1800},
            {"category": "Food & Tea Tasting", "amountBDT": 900},
            {"category": "National Park Entry & Rickshaw", "amountBDT": 300}
        ]
    else:
        return [
            {"category": "Local Transport", "amountBDT": 1200},
            {"category": "Accommodation", "amountBDT": 1800},
            {"category": "Fooding", "amountBDT": 1000}
        ]

def upload_image_to_vps(img_url, post_id, img_index):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }
    try:
        r = requests.get(img_url, headers=headers, timeout=15)
        if r.status_code != 200:
            print(f"      [Image Upload] Failed to download image from FB (Status code: {r.status_code})")
            return None
            
        upload_url = "https://bhromon.bpep.info/api/upload"
        upload_headers = {
            "X-Upload-Key": "bhromon_secure_upload_key_2026"
        }
        
        path = f"trip_logs/images/fb_{post_id}_{img_index}.jpg"
        files = {
            "file": (f"fb_{post_id}_{img_index}.jpg", r.content, "image/jpeg")
        }
        data = {
            "path": path
        }
        
        resp = requests.post(upload_url, headers=upload_headers, files=files, data=data, timeout=20)
        if resp.status_code == 200:
            json_data = resp.json()
            public_url = json_data.get("url")
            print(f"      [Image Upload] Successfully uploaded to VPS: {public_url}")
            return public_url
        else:
            print(f"      [Image Upload] VPS Upload failed: {resp.status_code} - {resp.text}")
            return None
    except Exception as e:
        print(f"      [Image Upload] Error uploading image to VPS: {e}")
        return None

def extract_posts_for_target(html, target, seen_signatures):
    soup = BeautifulSoup(html, "lxml")
    posts = []
    
    cards = []
    for card in soup.find_all("div", class_="x1yztbdb"):
        cards.append(card)
    for card in soup.find_all("div", class_="x1a2a7pz"):
        cards.append(card)
    for card in soup.find_all("div", role="article"):
        cards.append(card)
    for card in soup.find_all("div", attrs={"aria-posinset": True}):
        cards.append(card)
        
    for card in cards:
        body_paragraphs = []
        message_div = card.find("div", attrs={"data-ad-preview": "message"}) or card.find("div", attrs={"data-ad-comet-preview": "message"})
        
        if message_div:
            for p_tag in message_div.find_all("div", dir="auto"):
                txt = p_tag.get_text().strip()
                if txt and len(txt) > 20:
                    body_paragraphs.append(txt)
            if not body_paragraphs:
                body_paragraphs = [message_div.get_text().strip()]
        else:
            for d in card.find_all("div", dir="auto"):
                txt = d.get_text().strip()
                if txt and len(txt) > 60:
                    if not any(txt in existing for existing in body_paragraphs) and not any(existing in txt for existing in body_paragraphs):
                        txt_cleaned = clean_post_text(txt)
                        if txt_cleaned and len(txt_cleaned) > 60:
                            body_paragraphs.append(txt_cleaned)
                            
        if not body_paragraphs:
            continue
            
        full_text = "\n\n".join(body_paragraphs)
        if len(full_text) < 180:
            continue
            
        if full_text.strip().endswith("?") or full_text.count("?") > 3 or full_text.count("？") > 3:
            continue
            
        # Extract images
        images = []
        for img in card.find_all("img"):
            src = img.get("src", "")
            if src and "scontent" in src and "emoji" not in src and "rsrc" not in src:
                if src not in images:
                    images.append(src)
                    
        if not images:
            continue
            
        sig = " ".join(full_text.split())[:120]
        if sig in seen_signatures:
            continue
        
        post_id = hashlib.md5(sig.encode('utf-8')).hexdigest()[:12]
        
        posts.append({
            "post_id": post_id,
            "paragraphs": body_paragraphs,
            "full_text": full_text,
            "images": images[:4],
            "pin_id": target["pin_id"],
            "district": target["district"],
            "division": target["division"],
            "signature": sig
        })
        
    return posts

def main():
    print("==========================================================")
    print(" Bhromon - Targeted Seeding of Remaining Destinations      ")
    print("==========================================================\n")

    print("[1/5] Authenticating Google Cloud Clients...")
    try:
        token = get_fresh_access_token()
        creds = google.oauth2.credentials.Credentials(
            token=token,
            refresh_token=get_refresh_token(),
            token_uri="https://oauth2.googleapis.com/token",
            client_id="563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
            client_secret="j9iVZfS8kkCEFUPaAeJV0sAi"
        )
        db = firestore.Client(project=PROJECT_ID, credentials=creds)
        print("      Authentication [OK]")
    except Exception as e:
        print(f"      [FATAL] Authentication failed: {e}")
        sys.exit(1)

    print("[2/5] Loading Facebook Cookies...")
    if not os.path.exists(COOKIE_FILE):
        print(f"      [FATAL] Cookies file not found at {COOKIE_FILE}")
        sys.exit(1)

    with open(COOKIE_FILE, "r", encoding="utf-8") as f:
        cookies = json.load(f)

    formatted_cookies = []
    for c in cookies:
        if "name" in c and "value" in c:
            formatted_cookies.append({
                "name": c["name"],
                "value": str(c["value"]),
                "domain": c.get("domain", ".facebook.com"),
                "path": c.get("path", "/")
            })
    print(f"      Loaded {len(formatted_cookies)} cookies [OK]")

    print("[3/5] Starting Targeted Group Searches via Playwright...")
    posts_to_seed = []
    seen_signatures = set()

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1280, 'height': 800}
        )
        context.add_cookies(formatted_cookies)

        for target in SEARCH_TARGETS:
            query = target["query"]
            print(f"\n      Searching for query '{query}' ({target['district']})...")
            
            encoded_query = urllib.parse.quote(query)
            search_url = f"{SEARCH_GROUP}/search/?q={encoded_query}"
            
            try:
                page = context.new_page()
                page.goto(search_url, wait_until="domcontentloaded", timeout=40000)
                page.wait_for_timeout(6000)

                # Scroll 3 times to get a few search results
                for scroll_step in range(4):
                    page.evaluate("window.scrollBy(0, 1200)")
                    page.wait_for_timeout(2500)
                    
                    html = page.content()
                    step_posts = extract_posts_for_target(html, target, seen_signatures)
                    for post in step_posts:
                        # Add target info
                        posts_to_seed.append(post)
                        print(f"      [Extracted] Mapped to {target['district']}: {post['paragraphs'][0][:45]}...")
                        # If we have found 2 high quality posts for this target, we can proceed to next query
                        target_posts = [p for p in posts_to_seed if p["pin_id"] == target["pin_id"]]
                        if len(target_posts) >= 2:
                            break
                    
                    if len([p for p in posts_to_seed if p["pin_id"] == target["pin_id"]]) >= 2:
                        break

                page.close()
            except Exception as e:
                print(f"      [Error] Search failed for query '{query}': {e}")

        browser.close()

    print(f"\n[4/5] Extracted total of {len(posts_to_seed)} target travel stories.")

    print("[5/5] Uploading photos and seeding TripLogs to Firestore...")
    seeded_count = 0

    # Group by pin to limit seeding to 1 high-quality post per destination (max 2)
    seeded_per_pin = {}

    for idx, post in enumerate(posts_to_seed):
        pin_id = post["pin_id"]
        district = post["district"]
        division = post["division"]
        
        # Limit to 1 post per pin to keep it extremely fast and clean, but cover all
        if seeded_per_pin.get(pin_id, 0) >= 1:
            continue

        print(f"\n   -> Seeding Story [{idx+1}/{len(posts_to_seed)}] for {district}:")
        title_snippet = post["paragraphs"][0][:60] + "..." if len(post["paragraphs"][0]) > 60 else post["paragraphs"][0]
        print(f"      Title: {title_snippet}")
        print(f"      Raw images found: {len(post['images'])}")

        uploaded_image_urls = []
        for img_idx, img_url in enumerate(post["images"]):
            pub_url = upload_image_to_vps(img_url, post["post_id"], img_idx)
            if pub_url:
                uploaded_image_urls.append(pub_url)
                if len(uploaded_image_urls) >= 1: # 1 image per post is perfect and fast
                    break

        if not uploaded_image_urls:
            print("      [Skip] Story has no valid photos uploaded. Skipping.")
            continue

        blocks = []
        block_idx = 0
        
        for p_idx, p_content in enumerate(post["paragraphs"]):
            blocks.append({
                "id": f"txt_{post['post_id']}_{block_idx}",
                "type": "text",
                "content": p_content,
                "isBold": (p_idx == 0)
            })
            block_idx += 1
            
            if p_idx == 0 and len(uploaded_image_urls) > 0:
                blocks.append({
                    "id": f"img_{post['post_id']}_{block_idx}",
                    "type": "image",
                    "storageUrl": uploaded_image_urls[0],
                    "caption": f"{district} ভ্রমণ - Travelers of Bangladesh (ToB) গ্রুপ থেকে সংগৃহীত"
                })
                block_idx += 1

        title = f"{district} ভ্রমণ কাহিনী - Travelers of Bangladesh"
        if len(post["paragraphs"][0]) < 80:
            title = post["paragraphs"][0].split("।")[0].strip() + f" | {district} (ToB)"
        else:
            title = f"{district} ট্যুর গাইড ও ভ্রমণ অভিজ্ঞতা | {district} (ToB)"

        # Get coordinates from pin
        lat, lng = 23.6850, 90.3563 # default Bangladesh center
        try:
            pin_doc = db.collection('location_pins').document(pin_id).get()
            if pin_doc.exists:
                pin_val = pin_doc.to_dict()
                lat = pin_val.get("lat", lat)
                lng = pin_val.get("lng", lng)
        except Exception:
            pass

        trip_doc_id = f"trip_fb_groups_{post['post_id']}"
        trip_ref = db.collection('trip_logs').document(trip_doc_id)
        
        trip_data = {
            "tripId": trip_doc_id,
            "authorId": AUTHOR_UID,
            "title": title,
            "blocks": blocks,
            "routePoints": [{"latitude": lat, "longitude": lng}],
            "costItems": generate_cost_items(pin_id),
            "pinId": pin_id,
            "locationPinId": pin_id,
            "trustScore": 95,
            "helpfulVotes": 38,
            "lastConfirmed": firestore.SERVER_TIMESTAMP,
            "publishedAt": datetime.now(),
            "division": division,
            "district": district,
            "hidden": False,
            "hiddenReason": None,
            "tier": "pioneer"
        }

        try:
            trip_ref.set(trip_data)
            seeded_count += 1
            seeded_per_pin[pin_id] = seeded_per_pin.get(pin_id, 0) + 1
            print(f"      [Success] Document {trip_doc_id} written to Firestore.")
        except Exception as e:
            print(f"      [Failure] Failed to write document: {e}")

    print(f"\n==========================================================")
    print(f" Seeding Complete! Targeted {seeded_count} pins successfully seeded.")
    print("==========================================================")

if __name__ == "__main__":
    main()
