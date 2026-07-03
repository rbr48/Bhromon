import os
import json
import sqlite3
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from google.cloud import firestore
import google.oauth2.credentials

def get_firestore_client():
    p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
    if not os.path.exists(p):
        raise Exception(f"Firebase credentials file not found at {p}. Please log in using 'firebase login'.")
    with open(p, 'r') as f:
        data = json.load(f)
    access_token = data['tokens']['access_token']
    creds = google.oauth2.credentials.Credentials(access_token)
    db = firestore.Client(project='bhromon-ff801', credentials=creds)
    return db

def is_youtube_video_available(video_id):
    url = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={video_id}&format=json"
    try:
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode() == 200
    except Exception:
        return False

def check_video_batch(video_ids):
    results = {}
    with ThreadPoolExecutor(max_workers=25) as executor:
        futures = {executor.submit(is_youtube_video_available, vid_id): vid_id for vid_id in video_ids}
        for future in as_completed(futures):
            vid_id = futures[future]
            try:
                results[vid_id] = future.result()
            except Exception:
                results[vid_id] = False
    return results

def extract_video_id(url):
    if not url:
        return None
    if "youtube.com/watch?v=" in url:
        return url.split("watch?v=")[1].split("&")[0]
    elif "youtu.be/" in url:
        return url.split("youtu.be/")[1].split("?")[0]
    elif "youtube.com/embed/" in url:
        return url.split("embed/")[1].split("?")[0]
    return None

DEFAULT_VIDEOS = {
    "pin_coxsbazar": "https://www.youtube.com/watch?v=Uw0MBg1v8MY",
    "pin_sajek": "https://www.youtube.com/watch?v=b1KgEAUGp8A",
    "pin_sundarbans": "https://www.youtube.com/watch?v=25RBuWJ_TgE",
    "pin_bandarban": "https://www.youtube.com/watch?v=uflzHWpXgck",
    "pin_sreemangal": "https://www.youtube.com/watch?v=glB3lH8yo6M",
    "pin_ratargul": "https://www.youtube.com/watch?v=VRRguvaw99M",
    "pin_saintmartin": "https://www.youtube.com/watch?v=IO7MS11Prn8",
    "pin_lalbagh": "https://www.youtube.com/watch?v=QPkSVa8mNuU",
    "pin_ahsanmanzil": "https://www.youtube.com/watch?v=-aBX-oM6-3M",
    "pin_shatgombuj": "https://www.youtube.com/watch?v=MNzEOmAhXqg"
}

def main():
    # ─── 1. Clean up SQLite database ───
    from config import DB_PATH
    print(f"[Validator] Connecting to SQLite DB: {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    c.execute("SELECT video_id FROM videos")
    rows = c.fetchall()
    video_ids = [row["video_id"] for row in rows]
    print(f"[Validator] Found {len(video_ids)} videos in SQLite. Verifying availability...")
    
    availabilities = check_video_batch(video_ids)
    
    deleted_sqlite_count = 0
    for vid_id, available in availabilities.items():
        if not available:
            print(f"[Validator] SQLite: Video {vid_id} is unavailable. Deleting...")
            c.execute("DELETE FROM videos WHERE video_id = ?", (vid_id,))
            deleted_sqlite_count += 1
            
    conn.commit()
    conn.close()
    print(f"[Validator] SQLite: Cleaned up {deleted_sqlite_count} unavailable videos.")
    
    # ─── 2. Clean up Firestore ───
    db = get_firestore_client()
    print("[Validator] Connected to Firestore. Querying trip logs...")
    
    collections = ['trip_logs', 'archived_trip_logs']
    deleted_firestore_ids = set()
    
    for coll_name in collections:
        coll_ref = db.collection(coll_name)
        docs = list(coll_ref.stream())
        print(f"[Validator] Collection '{coll_name}': Found {len(docs)} documents.")
        
        doc_video_mappings = []
        for doc in docs:
            d = doc.to_dict()
            blocks = d.get('blocks', [])
            for idx, block in enumerate(blocks):
                if block.get('type') == 'video':
                    url = block.get('videoUrl') or block.get('storageUrl')
                    vid_id = extract_video_id(url)
                    if vid_id:
                        doc_video_mappings.append({
                            'doc': doc,
                            'block_idx': idx,
                            'video_id': vid_id,
                            'url': url
                        })
        
        if not doc_video_mappings:
            continue
            
        print(f"[Validator] Collection '{coll_name}': Found {len(doc_video_mappings)} YouTube video blocks. Verifying...")
        video_ids_to_check = [item['video_id'] for item in doc_video_mappings]
        video_availabilities = check_video_batch(video_ids_to_check)
        
        # Group updates per doc
        docs_to_update = {}
        for item in doc_video_mappings:
            doc = item['doc']
            vid_id = item['video_id']
            block_idx = item['block_idx']
            available = video_availabilities.get(vid_id, False)
            
            if not available:
                trip_id = doc.id
                # If it's a YouTube-only trip log (id starts with trip_yt_), delete the whole doc
                if trip_id.startswith("trip_yt_"):
                    print(f"[Validator] Firestore '{coll_name}': YouTube log {trip_id} has unavailable video {vid_id}. Deleting log...")
                    doc.reference.delete()
                    deleted_firestore_ids.add(trip_id)
                else:
                    # Otherwise, update the video URL in the blocks to a default valid video
                    pin_id = doc.to_dict().get('pinId')
                    default_url = DEFAULT_VIDEOS.get(pin_id)
                    if default_url:
                        if trip_id not in docs_to_update:
                            docs_to_update[trip_id] = {'doc_ref': doc.reference, 'blocks': doc.to_dict().get('blocks', [])}
                        
                        block = docs_to_update[trip_id]['blocks'][block_idx]
                        old_url = block.get('videoUrl') or block.get('storageUrl')
                        print(f"[Validator] Firestore '{coll_name}': Log {trip_id} has bad video {old_url} for pin {pin_id}. Replacing with {default_url}...")
                        
                        if 'videoUrl' in block:
                            block['videoUrl'] = default_url
                        if 'storageUrl' in block:
                            block['storageUrl'] = default_url
        
        # Apply updates
        for trip_id, update_data in docs_to_update.items():
            if trip_id not in deleted_firestore_ids:
                update_data['doc_ref'].update({'blocks': update_data['blocks']})
                print(f"[Validator] Firestore '{coll_name}': Updated video block in log {trip_id}.")
                
    print(f"[Validator] Firestore: Deleted {len(deleted_firestore_ids)} documents.")
    
    if deleted_firestore_ids:
        # ─── 3. Clean up linked IDs in location_pins ───
        print("[Validator] Scanning 'location_pins' to remove deleted trip log references...")
        pins_ref = db.collection('location_pins')
        pins = list(pins_ref.stream())
        
        for pin in pins:
            pin_data = pin.to_dict()
            linked_trips = pin_data.get('linkedTripIds', [])
            
            # Check if any deleted trip ID is in the list
            updated_trips = [tid for tid in linked_trips if tid not in deleted_firestore_ids]
            
            if len(updated_trips) != len(linked_trips):
                print(f"[Validator] Pin {pin.id}: Removing deleted references from linkedTripIds.")
                pin.reference.update({'linkedTripIds': updated_trips})
                
    print("[Validator] Cleanup finished successfully!")

if __name__ == "__main__":
    main()
