import os
import json
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
from google.cloud import firestore
import google.oauth2.credentials

def verify():
    p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
    with open(p, 'r') as f:
        data = json.load(f)
    access_token = data['tokens']['access_token']
    creds = google.oauth2.credentials.Credentials(access_token)
    db = firestore.Client(project='bhromon-ff801', credentials=creds)

    print("--- Verification Report ---")
    
    # 1. Check Explorers
    print("Checking Explorers:")
    for uid in ["author_rashed_a", "author_nusrat_i", "author_tanvir_h", "author_mitu_k"]:
        doc = db.collection('explorer_profiles').document(uid).get()
        if doc.exists:
            print(f"  [OK] Explorer profile exists: {doc.to_dict()['displayName']}")
        else:
            print(f"  [ERROR] Explorer profile {uid} not found!")

    # 2. Check Pins
    print("\nChecking Location Pins:")
    for pin_id in ["pin_sajek", "pin_coxsbazar", "pin_sundarbans", "pin_bandarban", "pin_ratargul", "pin_kuakata"]:
        doc = db.collection('location_pins').document(pin_id).get()
        if doc.exists:
            data = doc.to_dict()
            print(f"  [OK] Location Pin exists: {data['name']} (linked trips count: {len(data.get('linkedTripIds', []))})")
        else:
            print(f"  [ERROR] Pin {pin_id} not found!")

    # 3. Check Trip Logs
    print("\nChecking Seeded Trip Logs:")
    trips = [
        {"id": "trip_sajek_guide_2025", "col": "trip_logs"},
        {"id": "trip_cox_marine_2025", "col": "trip_logs"},
        {"id": "trip_sundarban_cruise_2024", "col": "archived_trip_logs"},
        {"id": "trip_ratargul_swamp_2024", "col": "archived_trip_logs"},
        {"id": "trip_bandarban_hills_2026", "col": "trip_logs"},
        {"id": "trip_kuakata_beach_2025", "col": "trip_logs"}
    ]
    
    for t in trips:
        doc = db.collection(t["col"]).document(t["id"]).get()
        if doc.exists:
            data = doc.to_dict()
            published_at = data.get('publishedAt')
            blocks = data.get('blocks', [])
            print(f"  [OK] TripLog {t['id']} found in '{t['col']}'")
            print(f"       Title: {data['title']}")
            print(f"       Published: {published_at}")
            print(f"       Blocks: {len(blocks)} blocks found.")
            for i, b in enumerate(blocks):
                print(f"         Block {i}: Type: {b.get('runtimeType')}, ID: {b.get('id')}")
        else:
            # Check other collection just in case
            other_col = "archived_trip_logs" if t["col"] == "trip_logs" else "trip_logs"
            doc2 = db.collection(other_col).document(t["id"]).get()
            if doc2.exists:
                print(f"  [WARNING] TripLog {t['id']} found in alternative collection '{other_col}'")
            else:
                print(f"  [ERROR] TripLog {t['id']} not found anywhere!")

if __name__ == "__main__":
    verify()
