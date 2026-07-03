import os
import json
import sys
from datetime import datetime, timezone
from google.cloud import firestore
import google.oauth2.credentials

sys.stdout.reconfigure(encoding='utf-8')

def get_firestore_client():
    p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
    if not os.path.exists(p):
        raise Exception(f"Firebase credentials file not found at {p}. Please log in using 'firebase login'.")
    with open(p, 'r') as f:
        data = json.load(f)
    access_token = data['tokens']['access_token']
    creds = google.oauth2.credentials.Credentials(access_token)
    return firestore.Client(project='bhromon-ff801', credentials=creds)

def has_youtube_video(doc_data):
    blocks = doc_data.get('blocks', [])
    for block in blocks:
        b_type = block.get('runtimeType') or block.get('type')
        if b_type == 'video':
            url = block.get('videoUrl') or block.get('storageUrl')
            if url and ("youtube.com" in url or "youtu.be" in url):
                return True
    return False

def main():
    db = get_firestore_client()
    collections = ['trip_logs', 'archived_trip_logs']
    
    deleted_trip_ids = set()
    cleaned_trip_ids = []
    
    print("--- STARTING CLEANUP AND REFINEMENT PROCESS ---")
    
    for coll_name in collections:
        coll_ref = db.collection(coll_name)
        docs = list(coll_ref.stream())
        print(f"\nProcessing collection '{coll_name}' ({len(docs)} documents)...")
        
        for doc in docs:
            d = doc.to_dict()
            trip_id = doc.id
            
            if not has_youtube_video(d):
                # 1. Delete post lacking YouTube video
                print(f"  [DELETE] Post '{trip_id}' (Title: '{d.get('title')}') has no YouTube video.")
                db.collection(coll_name).document(trip_id).delete()
                deleted_trip_ids.add(trip_id)
            else:
                # 2. Check if YouTube post was posted today (2026-06-23)
                pub_date = d.get('publishedAt')
                is_today = False
                if pub_date:
                    if isinstance(pub_date, datetime):
                        if pub_date.year == 2026 and pub_date.month == 6 and pub_date.day == 23:
                            is_today = True
                
                if is_today:
                    blocks = d.get('blocks', [])
                    # Filter out image blocks
                    new_blocks = [b for b in blocks if (b.get('runtimeType') or b.get('type')) != 'image']
                    
                    old_photo_count = sum(1 for b in blocks if (b.get('runtimeType') or b.get('type')) == 'image')
                    
                    if old_photo_count > 0:
                        print(f"  [CLEAN] YouTube post '{trip_id}' (Title: '{d.get('title')}') posted today. Removing {old_photo_count} photos.")
                        db.collection(coll_name).document(trip_id).update({
                            "blocks": new_blocks
                        })
                        cleaned_trip_ids.append(trip_id)
                        
    print(f"\nSuccessfully deleted {len(deleted_trip_ids)} posts without YouTube video links.")
    print(f"Successfully removed photos from {len(cleaned_trip_ids)} YouTube posts posted today.")
    
    # 3. Update Location Pins
    if deleted_trip_ids:
        print("\nUpdating location pins to remove deleted trip references...")
        pins_ref = db.collection('location_pins')
        pins = list(pins_ref.stream())
        for pin in pins:
            pin_data = pin.to_dict()
            linked_trips = pin_data.get('linkedTripIds', [])
            if any(tid in deleted_trip_ids for tid in linked_trips):
                new_linked_trips = [tid for tid in linked_trips if tid not in deleted_trip_ids]
                removed_count = len(linked_trips) - len(new_linked_trips)
                print(f"  Pin '{pin.id}' ('{pin_data.get('name')}'): Removing {removed_count} deleted references.")
                pins_ref.document(pin.id).update({
                    "linkedTripIds": new_linked_trips
                })
    else:
        print("\nNo deleted references to remove from location pins.")
        
    print("\n--- CLEANUP COMPLETE ---")

if __name__ == '__main__':
    main()
