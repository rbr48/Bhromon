import os
import json
from google.cloud import firestore
import google.oauth2.credentials

# Load Firebase CLI token
p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
data = json.load(open(p))
access_token = data['tokens']['access_token']

creds = google.oauth2.credentials.Credentials(access_token)
db = firestore.Client(project='bhromon-ff801', credentials=creds)

EXPLORERS = [
    {
        "uid": "author_rashed_a",
        "displayName": "Rashed Ahmed",
        "explorerScore": {
            "value": 842,
            "tier": "pioneer"
        },
        "tier": "pioneer",
        "badges": ["★ Pioneer", "★ Verified"],
        "division": "Dhaka",
        "createdAt": "2026-01-10T12:00:00Z",
        "isPioneer": True,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Rashed",
        "bio": "Avid hill trekker and explorer."
    },
    {
        "uid": "author_nusrat_i",
        "displayName": "Nusrat Islam",
        "explorerScore": {
            "value": 621,
            "tier": "verified"
        },
        "tier": "verified",
        "badges": ["★ Verified"],
        "division": "Khulna",
        "createdAt": "2026-02-15T08:30:00Z",
        "isPioneer": False,
        "isRegionExpert": True,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Nusrat",
        "bio": "Sundarbans and mangrove forest enthusiast."
    },
    {
        "uid": "author_tanvir_h",
        "displayName": "Tanvir Hasan",
        "explorerScore": {
            "value": 498,
            "tier": "community"
        },
        "tier": "community",
        "badges": ["✓ Community"],
        "division": "Sylhet",
        "createdAt": "2026-03-01T14:45:00Z",
        "isPioneer": False,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Tanvir",
        "bio": "Tea garden wanderer and photographer."
    },
    {
        "uid": "author_mitu_k",
        "displayName": "Mitu Khan",
        "explorerScore": {
            "value": 387,
            "tier": "community"
        },
        "tier": "community",
        "badges": ["✓ Community"],
        "division": "Chittagong",
        "createdAt": "2026-04-12T10:15:00Z",
        "isPioneer": False,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Mitu",
        "bio": "Cox's Bazar beach lover and local foodie."
    }
]

def seed_explorers():
    print("[Seeder] Uploading explorer profiles to Firestore...")
    for exp in EXPLORERS:
        ref = db.collection('explorer_profiles').document(exp["uid"])
        ref.set(exp)
        print(f"  + Seeded explorer: {exp['displayName']}")
    print(f"[Seeder] Successfully seeded {len(EXPLORERS)} explorer profiles.")

if __name__ == "__main__":
    seed_explorers()
