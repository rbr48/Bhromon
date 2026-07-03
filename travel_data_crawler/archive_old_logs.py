import os
import json
from google.cloud import firestore
import google.oauth2.credentials
from datetime import datetime, timezone

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

def migrate_old_logs():
    db = get_firestore_client()
    print("[Migration] Connected to Firestore. Querying trip logs...")
    
    logs_ref = db.collection('trip_logs')
    docs = list(logs_ref.stream())
    print(f"[Migration] Found {len(docs)} documents in 'trip_logs'.")
    
    now = datetime.now(timezone.utc)
    moved_count = 0
    
    for doc in docs:
        d = doc.to_dict()
        trip_id = doc.id
        
        # Resolve publication date
        pub = d.get('publishedAt')
        last = d.get('lastConfirmed')
        
        date = None
        if pub:
            date = pub
        elif last:
            date = last
            
        if date:
            # Normalize to datetime
            if not isinstance(date, datetime):
                try:
                    date = datetime.fromisoformat(date.replace('Z', '+00:00'))
                except Exception as e:
                    print(f"[Migration] Error parsing date '{date}' for document {trip_id}: {e}")
                    continue
            
            if date.tzinfo is None:
                date = date.replace(tzinfo=timezone.utc)
                
            delta = now - date
            if delta.days > 365:
                # Copy to archived_trip_logs
                print(f"[Migration] Moving {trip_id} (published {date.date()}) to 'archived_trip_logs'...")
                
                # Write to archived_trip_logs
                db.collection('archived_trip_logs').document(trip_id).set(d)
                
                # Delete from trip_logs
                db.collection('trip_logs').document(trip_id).delete()
                
                moved_count += 1

    print(f"[Migration] Successfully moved {moved_count} old documents to 'archived_trip_logs'.")

if __name__ == "__main__":
    migrate_old_logs()
