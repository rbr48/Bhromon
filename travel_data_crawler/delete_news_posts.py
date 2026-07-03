import os
import json
import sys
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

def main():
    db = get_firestore_client()
    collections = ['trip_logs', 'archived_trip_logs']
    
    deleted_trip_ids = set()
    
    print("--- STARTING NEWS ARTICLES DELETION PROCESS ---")
    
    for coll_name in collections:
        coll_ref = db.collection(coll_name)
        docs = list(coll_ref.stream())
        print(f"\nProcessing collection '{coll_name}' ({len(docs)} documents)...")
        
        for doc in docs:
            trip_id = doc.id
            if trip_id.startswith('trip_art_'):
                d = doc.to_dict()
                print(f"  [DELETE] News/Article Post '{trip_id}' (Title: '{d.get('title')}')")
                db.collection(coll_name).document(trip_id).delete()
                deleted_trip_ids.add(trip_id)
                
    print(f"\nSuccessfully deleted {len(deleted_trip_ids)} news/article posts.")
    
    # Update Location Pins
    if deleted_trip_ids:
        print("\nUpdating location pins to remove deleted news article references...")
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
        
    print("\n--- DELETION COMPLETE ---")

if __name__ == '__main__':
    main()
