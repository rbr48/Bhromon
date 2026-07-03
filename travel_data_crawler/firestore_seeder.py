import os
import json
import sqlite3
import random
from datetime import datetime
from google.cloud import firestore
import google.oauth2.credentials

# ─── Authenticated Firestore setup (Lazy Loaded) ──────────────────────────────
db = None

def get_firestore_client():
    global db
    if db is None:
        p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
        if not os.path.exists(p):
            raise Exception(f"Firebase credentials file not found at {p}. Please log in using 'firebase login'.")
        with open(p, 'r') as f:
            data = json.load(f)
        access_token = data['tokens']['access_token']
        creds = google.oauth2.credentials.Credentials(access_token)
        db = firestore.Client(project='bhromon-ff801', credentials=creds)
    return db

# ─── Define Location Pins (Real Destinations of Bangladesh) ───────────────────
LOCATIONS = [
    {
        "pinId": "pin_sajek",
        "name": "Sajek Valley",
        "geoHash": "w3ch",
        "lat": 23.3817,
        "lng": 92.2938,
        "trustTier": "pioneer",
        "division": "Chittagong",
        "district": "Rangamati",
        "createdByUid": "system",
        "keywords": ["sajek", "ruilui", "konglak", "clouds"]
    },
    {
        "pinId": "pin_coxsbazar",
        "name": "Cox's Bazar Beach",
        "geoHash": "w3bf",
        "lat": 21.4272,
        "lng": 91.9701,
        "trustTier": "pioneer",
        "division": "Chittagong",
        "district": "Cox's Bazar",
        "createdByUid": "system",
        "keywords": ["cox", "beach", "himchari", "inani", "sea", "ocean"]
    },
    {
        "pinId": "pin_sundarbans",
        "name": "Sundarbans Mangrove Forest",
        "geoHash": "w39c",
        "lat": 21.9497,
        "lng": 89.1833,
        "trustTier": "verified",
        "division": "Khulna",
        "district": "Khulna",
        "createdByUid": "system",
        "keywords": ["sundarban", "sundarbans", "mangrove", "tiger", "deer", "hiron point", "katka"]
    },
    {
        "pinId": "pin_bandarban",
        "name": "Bandarban Hills",
        "geoHash": "w3cc",
        "lat": 22.1953,
        "lng": 92.2184,
        "trustTier": "verified",
        "division": "Chittagong",
        "district": "Bandarban",
        "createdByUid": "system",
        "keywords": ["bandarban", "nilgiri", "chimbuk", "boga lake", "keokradong", "waterfall", "trekking"]
    },
    {
        "pinId": "pin_sreemangal",
        "name": "Sreemangal Tea Gardens",
        "geoHash": "w3fc",
        "lat": 24.3065,
        "lng": 91.7295,
        "trustTier": "verified",
        "division": "Sylhet",
        "district": "Moulvibazar",
        "createdByUid": "system",
        "keywords": ["sreemangal", "srimangal", "tea", "garden", "lawachara", "rainforest"]
    },
    {
        "pinId": "pin_ratargul",
        "name": "Ratargul Swamp Forest",
        "geoHash": "w3fg",
        "lat": 25.0064,
        "lng": 91.9312,
        "trustTier": "community",
        "division": "Sylhet",
        "district": "Sylhet",
        "createdByUid": "system",
        "keywords": ["ratargul", "swamp", "forest", "sylhet", "boat"]
    },
    {
        "pinId": "pin_saintmartin",
        "name": "Saint Martin's Island",
        "geoHash": "w3b3",
        "lat": 20.6279,
        "lng": 92.3234,
        "trustTier": "pioneer",
        "division": "Chittagong",
        "district": "Cox's Bazar",
        "createdByUid": "system",
        "keywords": ["martin", "martins", "island", "coral", "cheradip"]
    },
    {
        "pinId": "pin_lalbagh",
        "name": "Lalbagh Fort",
        "geoHash": "w3e3",
        "lat": 23.7189,
        "lng": 90.3882,
        "trustTier": "verified",
        "division": "Dhaka",
        "district": "Dhaka",
        "createdByUid": "system",
        "keywords": ["lalbagh", "fort", "shaista khan", "dhaka"]
    },
    {
        "pinId": "pin_ahsanmanzil",
        "name": "Ahsan Manzil",
        "geoHash": "w3e3",
        "lat": 23.7086,
        "lng": 90.4060,
        "trustTier": "verified",
        "division": "Dhaka",
        "district": "Dhaka",
        "createdByUid": "system",
        "keywords": ["ahsan", "manzil", "palace", "buriganga"]
    },
    {
        "pinId": "pin_shatgombuj",
        "name": "Shat Gombuj Mosque",
        "geoHash": "w3d3",
        "lat": 22.6744,
        "lng": 89.7417,
        "trustTier": "verified",
        "division": "Khulna",
        "district": "Bagerhat",
        "createdByUid": "system",
        "keywords": ["shat", "gombuj", "mosque", "sixty dome", "khan jahan"]
    }
]

# ─── High-Quality Enrichment Data for Compliance ─────────────────────────────
ENRICHMENT_DATA = {
    "pin_coxsbazar": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1589979482837-e74f2e145060?auto=format&fit=crop&w=800&q=80", "caption": "Sunset over Cox's Bazar beach"},
            {"url": "https://images.unsplash.com/photo-1544735716-392fe2489ffa?auto=format&fit=crop&w=800&q=80", "caption": "Inani Beach coral blocks"},
            {"url": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80", "caption": "Marine Drive scenic highway"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=Uw0MBg1v8MY", "caption": "Cox's Bazar Beach and Marine Drive Vlog"},
        "route": {
            "points": [
                {"latitude": 21.4522, "longitude": 91.9639},
                {"latitude": 21.4162, "longitude": 91.9842},
                {"latitude": 21.1856, "longitude": 92.0722}
            ],
            "description": "Marine Drive route along the coastline from Laboni beach to Inani"
        },
        "safety_notes": [
            {"text": "Pay close attention to flag signals on the beach. Red flag means swimming is strictly prohibited due to dangerous rip currents.", "level": "danger"},
            {"text": "Life jackets are available for rent at reasonable rates. Always swim in designated areas monitored by lifeguards.", "level": "info"}
        ],
        "cost_items": [
            {"label": "AC Bus ticket from Dhaka", "amountBDT": 1600, "category": "transport"},
            {"label": "Hotel room per night", "amountBDT": 3500, "category": "accommodation"},
            {"label": "Seafood meal platter", "amountBDT": 800, "category": "food"}
        ],
        "default_desc": "Cox's Bazar is the longest natural sandy beach in the world, stretching over 120 kilometers. It is located in the southeastern region of Bangladesh and is the country's most popular tourist destination. The sandy shores are perfect for relaxing, swimming, and watching breathtaking sunsets over the Bay of Bengal. Along Marine Drive, visitors can experience the beautiful scenery where green hills meet the blue ocean. Nearby attractions like Himchari Waterfall and Inani Coral Beach are also must-visit spots. Travel to Cox's Bazar is easy via direct bus, train, or flight from Dhaka."
    },
    "pin_sajek": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1628155930542-3c7a64e2c833?auto=format&fit=crop&w=800&q=80", "caption": "Sajek Valley morning clouds"},
            {"url": "https://images.unsplash.com/photo-1596422846543-75c6fc18a523?auto=format&fit=crop&w=800&q=80", "caption": "Konglak Para peak view"},
            {"url": "https://images.unsplash.com/photo-1616036740257-9449ea1f6605?auto=format&fit=crop&w=800&q=80", "caption": "Beautiful wooden cottage in Sajek"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=b1KgEAUGp8A", "caption": "Sajek Valley Complete Travel Guide"},
        "route": {
            "points": [
                {"latitude": 23.1192, "longitude": 91.9686},
                {"latitude": 23.2543, "longitude": 92.0654},
                {"latitude": 23.3817, "longitude": 92.2938}
            ],
            "description": "Scenic mountain route from Khagrachari to Sajek via Chander Gari"
        },
        "safety_notes": [
            {"text": "Travel in a military convoy is mandatory from Dighinala to Sajek. Convoy starts at 10:00 AM and 3:00 PM; don't miss it.", "level": "warning"},
            {"text": "Mobile network coverage is limited; only Teletalk and Robi work well in some spots. Keep cash handy as there are no ATMs.", "level": "info"}
        ],
        "cost_items": [
            {"label": "Chander Gari jeep rent (shared)", "amountBDT": 1500, "category": "transport"},
            {"label": "Wooden cottage stay", "amountBDT": 4000, "category": "accommodation"},
            {"label": "Bamboo Chicken local dinner", "amountBDT": 700, "category": "food"}
        ],
        "default_desc": "Sajek Valley is an emerging tourist spot in Bangladesh situated among the hills of the Kasalong range of mountains in Sajek union, Baghaichhari Upazila in Rangamati District. The valley is 1,800 feet above sea level. Sajek valley is known as the Queen of Hills & Roof of Rangamati. The valley is famous for its natural beauty. The valley is surrounded by hills, forest, and grasslands. Clouds gather over the valley in the early morning, offering an unforgettable sight for tourists."
    },
    "pin_sundarbans": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1611001716885-b340a558ac64?auto=format&fit=crop&w=800&q=80", "caption": "Royal Bengal Tiger in Sundarbans"},
            {"url": "https://images.unsplash.com/photo-1589909202802-8f4aadce1849?auto=format&fit=crop&w=800&q=80", "caption": "Mangrove aerial tree roots"},
            {"url": "https://images.unsplash.com/photo-1500627869374-13cd993b1115?auto=format&fit=crop&w=800&q=80", "caption": "Sundarbans river boat canal"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=25RBuWJ_TgE", "caption": "Sundarbans Tiger Reserve Cruise"},
        "route": {
            "points": [
                {"latitude": 22.8097, "longitude": 89.5644},
                {"latitude": 22.4842, "longitude": 89.6083},
                {"latitude": 21.8543, "longitude": 89.7824}
            ],
            "description": "Cruising down the Rupsha River from Khulna Launch Ghat to Katka"
        },
        "safety_notes": [
            {"text": "Never wander off the designated forest trails alone. Sundarbans is home to wild tigers, saltwater crocodiles, and venomous snakes.", "level": "danger"},
            {"text": "Ensure your tour group has an armed forest guard. Do not throw plastic bottles or garbage into the river canals.", "level": "warning"}
        ],
        "cost_items": [
            {"label": "3-day launch cruise package", "amountBDT": 15000, "category": "accommodation"},
            {"label": "Forest entry & guard charge", "amountBDT": 1200, "category": "general"},
            {"label": "Local country boat ride", "amountBDT": 500, "category": "transport"}
        ],
        "default_desc": "The Sundarbans is a mangrove area in the delta formed by the confluence of the Ganges, Brahmaputra and Meghna Rivers in the Bay of Bengal. It spans from the Hooghly River in India's state of West Bengal to the Baleswar River in Bangladesh's division of Khulna. It comprises closed and open mangrove forests, land temporally used for agricultural purpose, mudflats and barren land, and is intersected by multiple tidal streams and channels. It is world-famous as the home of the majestic Royal Bengal Tiger."
    },
    "pin_bandarban": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1605649487212-47bdab064df7?auto=format&fit=crop&w=800&q=80", "caption": "Bandarban mountain peak view"},
            {"url": "https://images.unsplash.com/photo-1583212292454-1fe6229603b7?auto=format&fit=crop&w=800&q=80", "caption": "Nilgiri cloud touch deck"},
            {"url": "https://images.unsplash.com/photo-1590001155093-a3c66ab0c3ff?auto=format&fit=crop&w=800&q=80", "caption": "Boga Lake trek base"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=uflzHWpXgck", "caption": "Bandarban Trekking & Travel Guide"},
        "route": {
            "points": [
                {"latitude": 22.1953, "longitude": 92.2184},
                {"latitude": 22.0343, "longitude": 92.3562},
                {"latitude": 21.9543, "longitude": 92.5186}
            ],
            "description": "Trekking route from Bandarban Town to Boga Lake and Keokradong Peak"
        },
        "safety_notes": [
            {"text": "Ensure you register your name at the local army camp before trekking Keokradong. Hiring a local guide is mandatory.", "level": "danger"},
            {"text": "Hilly roads are very steep. Do not drive yourself; rely on experienced local Chander Gari drivers.", "level": "warning"}
        ],
        "cost_items": [
            {"label": "Local guide charge per day", "amountBDT": 1500, "category": "general"},
            {"label": "Boga Lake cottage stay", "amountBDT": 1500, "category": "accommodation"},
            {"label": "Chander Gari jeep rent to Nilgiri", "amountBDT": 4500, "category": "transport"}
        ],
        "default_desc": "Bandarban is a district in South-Eastern Bangladesh, and a part of the Chittagong Division and Chittagong Hill Tracts. Bandarban is regarded as one of the most exotic tourist destinations in Bangladesh. It features the highest peaks of the country like Keokradong and Tajingdong, beautiful natural waterfalls like Nafakhum and Amiakhum, and the serene Boga Lake. The region is rich with tribal cultures and breathtaking landscapes."
    },
    "pin_sreemangal": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1555597673-b21d5c935865?auto=format&fit=crop&w=800&q=80", "caption": "Tea garden tea pluckers"},
            {"url": "https://images.unsplash.com/photo-1563245372-f21724e3856d?auto=format&fit=crop&w=800&q=80", "caption": "Lawachara national park trail"},
            {"url": "https://images.unsplash.com/photo-1594913785162-e6785b49eed5?auto=format&fit=crop&w=800&q=80", "caption": "Seven layer tea cup"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=glB3lH8yo6M", "caption": "Sreemangal Tea Estates Tour Guide"},
        "route": {
            "points": [
                {"latitude": 24.3094, "longitude": 91.7312},
                {"latitude": 24.2789, "longitude": 91.7562},
                {"latitude": 24.3243, "longitude": 91.7824}
            ],
            "description": "Cycling route from Sreemangal Station through Finlay Tea Estate to Lawachara Forest"
        },
        "safety_notes": [
            {"text": "Do not touch or pluck tea leaves without permission. Watch out for leeches in Lawachara forest during the monsoon.", "level": "warning"},
            {"text": "Try the famous 7-layer tea at Nilkantha Tea Cabin. Cycle rentals are widely available and a great way to explore.", "level": "info"}
        ],
        "cost_items": [
            {"label": "Eco-resort stay per night", "amountBDT": 3000, "category": "accommodation"},
            {"label": "Local guide at Lawachara", "amountBDT": 500, "category": "general"},
            {"label": "Bicycle rental per day", "amountBDT": 250, "category": "transport"}
        ],
        "default_desc": "Sreemangal is known as the tea capital of Bangladesh due to the large number of tea gardens in the area. For miles and miles, tourists can see green tea gardens rolling over the hills. Sreemangal also hosts the Lawachara National Park, which is a significant semi-evergreen forest and home to the endangered hoolock gibbons. It is a peaceful getaway, perfect for nature walks, birdwatching, and tasting the unique multi-layered tea."
    },
    "pin_ratargul": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1601918774946-25832a4be0d6?auto=format&fit=crop&w=800&q=80", "caption": "Submerged trees in swamp forest"},
            {"url": "https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=800&q=80", "caption": "Traditional wooden boat in swamp"},
            {"url": "https://images.unsplash.com/photo-1472396961693-142e6e269027?auto=format&fit=crop&w=800&q=80", "caption": "Lush green swamp canopy"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=VRRguvaw99M", "caption": "Exploring Ratargul Swamp Forest"},
        "route": {
            "points": [
                {"latitude": 24.9034, "longitude": 91.8686},
                {"latitude": 24.9943, "longitude": 91.9164},
                {"latitude": 25.0064, "longitude": 91.9312}
            ],
            "description": "CNG route from Sylhet town to Ratargul Boat Ghat, followed by boat trip to Watchtower"
        },
        "safety_notes": [
            {"text": "Keep your hands inside the boat. Snakes and insects hang from the submerged trees during high water season.", "level": "warning"},
            {"text": "The boat fare is fixed by the local cooperative association. Rent an umbrella/hat to shield yourself from sun or rain.", "level": "info"}
        ],
        "cost_items": [
            {"label": "CNG auto rent from Sylhet (round trip)", "amountBDT": 1200, "category": "transport"},
            {"label": "Swamp boat rent (max 4 persons)", "amountBDT": 850, "category": "general"},
            {"label": "Watchtower entry ticket", "amountBDT": 50, "category": "general"}
        ],
        "default_desc": "Ratargul Swamp Forest is a freshwater swamp forest located in Gowainghat, Sylhet, Bangladesh. It is the only swamp forest located in Bangladesh and one of the few freshwater swamp forests in the world. The forest is naturally conserved under the Department of Forestry. It goes under 20-30 feet of water during the monsoon season, making it an amazing destination to explore by small wooden boats as you glide through the branches of submerged evergreen trees."
    },
    "pin_saintmartin": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1506929562872-bb421503ef21?auto=format&fit=crop&w=800&q=80", "caption": "Coconut trees on Saint Martin beach"},
            {"url": "https://images.unsplash.com/photo-1505118380757-91f5f5632de0?auto=format&fit=crop&w=800&q=80", "caption": "Crystal clear blue sea water"},
            {"url": "https://images.unsplash.com/photo-1519046904884-53103b34b206?auto=format&fit=crop&w=800&q=80", "caption": "Sandy beach sunset on the island"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=IO7MS11Prn8", "caption": "Saint Martin Island Travel Guide"},
        "route": {
            "points": [
                {"latitude": 20.8986, "longitude": 92.2982},
                {"latitude": 20.6312, "longitude": 92.3214},
                {"latitude": 20.5743, "longitude": 92.3416}
            ],
            "description": "Ferry cruise from Teknaf Ship Ghat to St Martin jetty, then walking to Chera Dwip"
        },
        "safety_notes": [
            {"text": "Ferry services to the island are suspended during rough weather (typically May to October). Always book tickets in advance.", "level": "warning"},
            {"text": "Walking on raw coral blocks can cause deep cuts. Do not collect or take corals away from the island as it is ecologically sensitive.", "level": "danger"}
        ],
        "cost_items": [
            {"label": "Ship ticket (Teknaf round trip)", "amountBDT": 1500, "category": "transport"},
            {"label": "Bicycle hire on the island", "amountBDT": 300, "category": "transport"},
            {"label": "Coconut water and local snacks", "amountBDT": 200, "category": "food"}
        ],
        "default_desc": "St. Martin's Island is a small island in the northeastern part of the Bay of Bengal, about 9 km south of the tip of the Cox's Bazar-Teknaf peninsula, and forming the southernmost part of Bangladesh. There is a small adjoining island that is separated at high tide, called Chera Dwip. It is the only coral island in Bangladesh. With its crystal clear blue waters, coconut trees, fresh seafood, and peaceful vibe, it is a paradise for travelers."
    },
    "pin_lalbagh": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1627896157734-4d7d4388f24b?auto=format&fit=crop&w=800&q=80", "caption": "Tomb of Pari Bibi at Lalbagh Fort"},
            {"url": "https://images.unsplash.com/photo-1599818814757-ba5ef30e5f2b?auto=format&fit=crop&w=800&q=80", "caption": "Fort gardens and pathways"},
            {"url": "https://images.unsplash.com/photo-1608958416805-4c07b66dfaa8?auto=format&fit=crop&w=800&q=80", "caption": "Mughal architecture detail gate"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=QPkSVa8mNuU", "caption": "Lalbagh Fort Historical Guide"},
        "route": {
            "points": [
                {"latitude": 23.7328, "longitude": 90.3982},
                {"latitude": 23.7256, "longitude": 90.3994},
                {"latitude": 23.7189, "longitude": 90.3882}
            ],
            "description": "Rickshaw route from Dhaka University (TSC) through Chankharpul to Lalbagh Fort"
        },
        "safety_notes": [
            {"text": "The fort is closed on Sundays and half-day on Mondays. Entry ticket is 30 BDT for Bangladeshi nationals.", "level": "info"},
            {"text": "Watch out for pickpockets in the crowded streets of Old Dhaka leading to the fort.", "level": "warning"}
        ],
        "cost_items": [
            {"label": "Rickshaw ride from TSC", "amountBDT": 80, "category": "transport"},
            {"label": "Entry ticket fee", "amountBDT": 30, "category": "general"},
            {"label": "Old Dhaka Biryani lunch", "amountBDT": 250, "category": "food"}
        ],
        "default_desc": "Lalbagh Fort is an incomplete 17th-century Mughal fort complex that stands before the Buriganga River in the southwestern part of Dhaka, Bangladesh. The construction was started in 1678 AD by Mughal Subahdar Muhammad Azam Shah, who was the son of Emperor Aurangzeb. It houses three outstanding monuments: the Mosque, the Tomb of Pari Bibi, and the Diwan-i-Aam palace, surrounded by beautiful Mughal gardens."
    },
    "pin_ahsanmanzil": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1605276374104-dee2a0ed3cd6?auto=format&fit=crop&w=800&q=80", "caption": "Ahsan Manzil Palace front facade"},
            {"url": "https://images.unsplash.com/photo-1590001155093-a3c66ab0c3ff?auto=format&fit=crop&w=800&q=80", "caption": "Historical stairs and domes"},
            {"url": "https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80", "caption": "Palace lawn and gardens"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=-aBX-oM6-3M", "caption": "Ahsan Manzil Pink Palace Tour"},
        "route": {
            "points": [
                {"latitude": 23.7252, "longitude": 90.4124},
                {"latitude": 23.7024, "longitude": 90.4112},
                {"latitude": 23.7086, "longitude": 90.4060}
            ],
            "description": "Route from Gulistan Bus Terminal to Sadarghat launch terminal, then short walk to Ahsan Manzil"
        },
        "safety_notes": [
            {"text": "Electronic ticketing is required; purchase your ticket online before arrival. Closed on Thursdays.", "level": "info"},
            {"text": "Sadarghat area is extremely crowded and noisy. Keep your belongings secure at all times.", "level": "warning"}
        ],
        "cost_items": [
            {"label": "Ahsan Manzil online ticket", "amountBDT": 40, "category": "general"},
            {"label": "Rowboat ride in Buriganga river", "amountBDT": 150, "category": "transport"},
            {"label": "Old Dhaka Bakarkhani snack", "amountBDT": 50, "category": "food"}
        ],
        "default_desc": "Ahsan Manzil was the official residential palace and seat of the Nawab of Dhaka. The building is situated at Kumartoli along the banks of the Buriganga River in Dhaka, Bangladesh. Construction was started in 1859 and completed in 1872. Painted in a striking pink color, it is a masterpiece of Indo-Saracenic Revival architecture and now serves as a popular national museum, showcasing historical artifacts and lifestyle of the Nawabs."
    },
    "pin_shatgombuj": {
        "images": [
            {"url": "https://images.unsplash.com/photo-1603566675083-d5d14dfb0e2b?auto=format&fit=crop&w=800&q=80", "caption": "Sixty Dome Mosque frontal view"},
            {"url": "https://images.unsplash.com/photo-1582407947304-fd86f028f716?auto=format&fit=crop&w=800&q=80", "caption": "Mughal brick arches interior"},
            {"url": "https://images.unsplash.com/photo-1563245372-f21724e3856d?auto=format&fit=crop&w=800&q=80", "caption": "Mosque archaeological park lawn"}
        ],
        "video": {"url": "https://www.youtube.com/watch?v=MNzEOmAhXqg", "caption": "Shat Gombuj Mosque Archaeological Site"},
        "route": {
            "points": [
                {"latitude": 22.6586, "longitude": 89.7892},
                {"latitude": 22.6612, "longitude": 89.7614},
                {"latitude": 22.6744, "longitude": 89.7417}
            ],
            "description": "Local auto route from Bagerhat Town Center via Khan Jahan Ali Shrine to Shat Gombuj Mosque"
        },
        "safety_notes": [
            {"text": "Dress conservatively when entering the active prayer halls of this historic mosque. A museum is located inside.", "level": "info"},
            {"text": "Avoid visiting during Friday mid-day prayers if you are not joining the congregation, as it gets very crowded.", "level": "warning"}
        ],
        "cost_items": [
            {"label": "Local auto ride from Bagerhat", "amountBDT": 50, "category": "transport"},
            {"label": "Mosque & museum entry ticket", "amountBDT": 30, "category": "general"},
            {"label": "Fresh coconut water by Ghora Dighi", "amountBDT": 60, "category": "food"}
        ],
        "default_desc": "The Sixty Dome Mosque (Shat Gombuj Mosque) is a UNESCO World Heritage Site in Bagerhat, Bangladesh. It is the largest mosque in Bangladesh from the Sultanate period (1352-1576). It was built during the Bengal Sultanate by Khan Jahan Ali, a saint-general who established a Muslim colony in the sundrenched delta. The mosque has 77 low domes and 11 arched doorways, showing classic early Islamic brick architecture."
    }
}

def map_location_for_text(text):
    text_lower = text.lower()
    for loc in LOCATIONS:
        for keyword in loc["keywords"]:
            if keyword in text_lower:
                return loc
    return None

def clean_none(val, default):
    return val if val is not None else default

def parse_date(date_str):
    try:
        # e.g. 'Sun, 01 Feb 2026 08:00:00 GMT'
        return datetime.strptime(date_str, '%a, %d %b %Y %H:%M:%S %Z')
    except:
        try:
            # e.g. '2026-06-11 00:06:37'
            return datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
        except:
            return datetime.utcnow()

def is_youtube_video_available(video_id):
    import urllib.request
    import urllib.error
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

def clear_collection(db, collection_name):
    print(f"[Seeder] Clearing collection '{collection_name}'...")
    docs = db.collection(collection_name).list_documents()
    deleted = 0
    batch = db.batch()
    for doc in docs:
        batch.delete(doc)
        deleted += 1
        if deleted % 500 == 0:
            batch.commit()
            batch = db.batch()
    batch.commit()
    print(f"[Seeder] Cleared {deleted} documents from '{collection_name}'.")

CURATED_PRO_TIPS = [
    {
        "tipId": "tip_sajek_transport",
        "locationPinId": "pin_sajek",
        "authorId": "travel_expert_sajek",
        "text": "Hire a registered Chander Gari (open jeep) from Khagrachhari to Sajek. Make sure you arrive at Dighinala Army Camp before the morning escort at 10:00 AM or the afternoon escort at 3:00 PM to travel safely in the military convoy.",
        "category": "transport",
    },
    {
        "tipId": "tip_sajek_accommodation",
        "locationPinId": "pin_sajek",
        "authorId": "travel_expert_sajek",
        "text": "Book cottages in Sajek Valley at least 2-3 weeks in advance, especially for weekend stays. Cottages on the Ruilui Para side offer spectacular sunset and valley views, while Konglak Para is higher but offers fewer amenities.",
        "category": "accommodation",
    },
    {
        "tipId": "tip_sajek_general",
        "locationPinId": "pin_sajek",
        "authorId": "travel_expert_sajek",
        "text": "Mobile network connectivity in Sajek is limited. Teletalk offers the most stable signal, followed by Robi. Keep power banks charged since electricity is mostly solar-powered and only available at night.",
        "category": "general",
    },
    {
        "tipId": "tip_cox_safety",
        "locationPinId": "pin_coxsbazar",
        "authorId": "travel_expert_cox",
        "text": "Always check the warning flags set up by lifesavers at the beach before swimming. A red flag indicates dangerous undercurrents and high tide—do not swim when the red flag is hoisted. Swim only in designated safe zones.",
        "category": "safety",
    },
    {
        "tipId": "tip_cox_transport",
        "locationPinId": "pin_coxsbazar",
        "authorId": "travel_expert_cox",
        "text": "For scenic transit to Inani Beach or Himchari, rent an electric easy-bike (Tomtom) from Kolatoli point. Negotiate the fare beforehand, or share a ride with others to reduce your travel expenses.",
        "category": "transport",
    },
    {
        "tipId": "tip_cox_food",
        "locationPinId": "pin_coxsbazar",
        "authorId": "travel_expert_cox",
        "text": "For authentic local seafood, try the beachside shacks at Sugandha or Kolatoli. Ask for fresh Rupchanda (Pomfret) or Coral fish cooked to order, and always try the traditional dried fish bhorta (Shutki).",
        "category": "food",
    },
    {
        "tipId": "tip_sundarbans_permit",
        "locationPinId": "pin_sundarbans",
        "authorId": "travel_expert_sundar",
        "text": "Visiting the Sundarbans requires a prior permit from the Forest Department, usually arranged by registered tour operators. Foreign nationals must pay a higher entry fee and carry passport copies.",
        "category": "general",
    },
    {
        "tipId": "tip_sundarbans_safety",
        "locationPinId": "pin_sundarbans",
        "authorId": "travel_expert_sundar",
        "text": "Do not wander off from your tour group or deep into the forest unaccompanied. Always follow the forest guards carrying licensed arms, as wild tigers and crocodiles are a real hazard.",
        "category": "safety",
    },
    {
        "tipId": "tip_sundarbans_transport",
        "locationPinId": "pin_sundarbans",
        "authorId": "travel_expert_sundar",
        "text": "Choose a launch tour package with a reputation for safety. Check if the vessel has clean drinking water, life jackets, and a silent generator to avoid disturbing the wildlife.",
        "category": "transport",
    },
    {
        "tipId": "tip_bandarban_permit",
        "locationPinId": "pin_bandarban",
        "authorId": "travel_expert_bandar",
        "text": "To travel to Boga Lake or Keokradong, you must register your name and details at the Ruma Bazar Army Camp. Hiring a local guide is mandatory for the trek up Keokradong.",
        "category": "transport",
    },
    {
        "tipId": "tip_bandarban_safety",
        "locationPinId": "pin_bandarban",
        "authorId": "travel_expert_bandar",
        "text": "The road to Nilgiri is steep with sharp hairpin turns. Hire experienced drivers and ensure the vehicle's brakes and tires are in top condition.",
        "category": "safety",
    },
    {
        "tipId": "tip_bandarban_accommodation",
        "locationPinId": "pin_bandarban",
        "authorId": "travel_expert_bandar",
        "text": "For a peaceful stay, choose resorts near Nilgiri or Chimbuk rather than Bandarban town. Bring mosquito repellent and anti-malarial medication as hilly areas have higher malaria risks.",
        "category": "accommodation",
    },
    {
        "tipId": "tip_sreemangal_food",
        "locationPinId": "pin_sreemangal",
        "authorId": "travel_expert_sree",
        "text": "Do not leave Sreemangal without trying the famous 7-layer tea at Nilkantha Tea Cabin. The layers are made of different grades of local tea and spices, creating a unique visual and taste experience.",
        "category": "food",
    },
    {
        "tipId": "tip_sreemangal_general",
        "locationPinId": "pin_sreemangal",
        "authorId": "travel_expert_sree",
        "text": "When visiting the Lawachara National Park, hire an official forest guide at the gate. This helps you spot hoolock gibbons, bark deer, and rare bird species while staying on designated trails.",
        "category": "general",
    },
    {
        "tipId": "tip_sreemangal_accommodation",
        "locationPinId": "pin_sreemangal",
        "authorId": "travel_expert_sree",
        "text": "Stay in an eco-cottage near Radhanagar to experience tea garden life. Many cottages offer home-cooked local meals and bicycle rentals to explore the nearby trails.",
        "category": "accommodation",
    },
    {
        "tipId": "tip_ratargul_transport",
        "locationPinId": "pin_ratargul",
        "authorId": "travel_expert_ratar",
        "text": "Hire a wooden boat (Dinghy) from the Ratargul Boat Ghat. The local cooperative fixes boat rent rates, so check the official rate chart before paying. A boat holds up to 4-5 people.",
        "category": "transport",
    },
    {
        "tipId": "tip_ratargul_timing",
        "locationPinId": "pin_ratargul",
        "authorId": "travel_expert_ratar",
        "text": "The best time to visit Ratargul is during the monsoon (July to October) when the forest is completely flooded. In winter, the water dries up, and boats cannot navigate the swamp.",
        "category": "general",
    },
    {
        "tipId": "tip_ratargul_safety",
        "locationPinId": "pin_ratargul",
        "authorId": "travel_expert_ratar",
        "text": "Watch out for low-hanging branches and tree snakes while boating through the dense canopy. Avoid touching the submerged trees or dipping your hands in the water.",
        "category": "safety",
    },
    {
        "tipId": "tip_stmartin_transport",
        "locationPinId": "pin_saintmartin",
        "authorId": "travel_expert_stmartin",
        "text": "Ships to Saint Martin's operate only from November to March from Teknaf or Cox's Bazar. Book your return ship tickets in advance, as tickets sell out quickly during peak winter season.",
        "category": "transport",
    },
    {
        "tipId": "tip_stmartin_safety",
        "locationPinId": "pin_saintmartin",
        "authorId": "travel_expert_stmartin",
        "text": "Plastic pollution is a severe threat to the island's coral ecosystem. Bring your trash back to the mainland and avoid buying souvenirs made from coral or turtle shells.",
        "category": "safety",
    },
    {
        "tipId": "tip_stmartin_food",
        "locationPinId": "pin_saintmartin",
        "authorId": "travel_expert_stmartin",
        "text": "Enjoy fresh coconut water (Dab) on the beach; Saint Martin's is famous for sweet coconuts. Try locally caught red snapper, lobster, and koral fish cooked to order.",
        "category": "food",
    },
    {
        "tipId": "tip_lalbagh_general",
        "locationPinId": "pin_lalbagh",
        "authorId": "travel_expert_lalbagh",
        "text": "Lalbagh Fort is closed on Sundays and half-day on Mondays. Entry ticket is 30 BDT for Bangladeshi nationals. Make sure to visit the museum inside the Diwan-i-Aam palace.",
        "category": "general",
    },
    {
        "tipId": "tip_lalbagh_safety",
        "locationPinId": "pin_lalbagh",
        "authorId": "travel_expert_lalbagh",
        "text": "Keep your valuables safe, as the streets leading to the fort in Old Dhaka are extremely crowded and active. Hire a rickshaw from Dhaka University area for a direct, scenic transit.",
        "category": "safety",
    },
    {
        "tipId": "tip_ahsanmanzil_general",
        "locationPinId": "pin_ahsanmanzil",
        "authorId": "travel_expert_ahsan",
        "text": "Ahsan Manzil requires online e-tickets to be purchased before arrival. It is closed on Thursdays. Ensure you book your slot on the official archaeological department website.",
        "category": "general",
    },
    {
        "tipId": "tip_ahsanmanzil_transport",
        "locationPinId": "pin_ahsanmanzil",
        "authorId": "travel_expert_ahsan",
        "text": "Avoid visiting during rush hours, as the Sadarghat launch terminal nearby attracts massive congestion. Try renting a local wooden rowboat on the Buriganga river for a view of the palace from the water.",
        "category": "transport",
    },
    {
        "tipId": "tip_sixtydome_general",
        "locationPinId": "pin_shatgombuj",
        "authorId": "travel_expert_sixtydome",
        "text": "Dress modestly when visiting this active house of worship. Shoes must be removed before entering the main prayer hall. A small museum on the premises exhibits Sultanate-era artifacts.",
        "category": "general",
    },
    {
        "tipId": "tip_sixtydome_food",
        "locationPinId": "pin_shatgombuj",
        "authorId": "travel_expert_sixtydome",
        "text": "Bagerhat is famous for high-quality coconut products. Try local sweets made from fresh coconut milk and date palm jaggery sold by vendors near the mosque.",
        "category": "food",
    },
]

def seed_database():
    db = get_firestore_client()
    
    from config import DB_PATH
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    print("[Seeder] Connected to SQLite travel_data.db")

    # 1. Clear existing ProTips and seed new curated ones
    clear_collection(db, 'pro_tips')
    print("[Seeder] Uploading curated pro tips to Firestore...")
    linked_tips = {loc["pinId"]: [] for loc in LOCATIONS}
    for tip in CURATED_PRO_TIPS:
        tip_ref = db.collection('pro_tips').document(tip["tipId"])
        tip_ref.set({
            "tipId": tip["tipId"],
            "locationPinId": tip["locationPinId"],
            "authorId": tip["authorId"],
            "text": tip["text"],
            "category": tip["category"],
            "helpfulVotes": random.randint(30, 80),
            "outdatedVotes": 0,
            "lastConfirmed": firestore.SERVER_TIMESTAMP,
            "decayStatus": "fresh",
            "hidden": False
        })
        linked_tips[tip["locationPinId"]].append(tip["tipId"])

    # 2. Seed Location Pins
    print("[Seeder] Uploading location pins to Firestore...")
    for loc in LOCATIONS:
        pin_ref = db.collection('location_pins').document(loc["pinId"])
        pin_ref.set({
            "pinId": loc["pinId"],
            "name": loc["name"],
            "geoHash": loc["geoHash"],
            "lat": loc["lat"],
            "lng": loc["lng"],
            "trustTier": loc["trustTier"],
            "lastConfirmed": firestore.SERVER_TIMESTAMP,
            "linkedTripIds": [],
            "linkedTipIds": [],
            "division": loc["division"],
            "district": loc["district"],
            "createdByUid": loc["createdByUid"]
        })
    print(f"[Seeder] Uploaded {len(LOCATIONS)} location pins.")

    # Track linked IDs per pin to update locations collection later
    linked_trips = {loc["pinId"]: [] for loc in LOCATIONS}

    # 3. Seed Articles as High Quality TripLogs (partition by age) (BYPASSED)
    print("[Seeder] Article seeding is bypassed as per user request.")
    trip_count = 0
    now = datetime.utcnow()

    # 4. Seed YouTube Videos as High Quality TripLogs
    c.execute("SELECT * FROM videos LIMIT 40")  # Seed top 40 youtube videos
    videos = c.fetchall()
    print(f"[Seeder] Found {len(videos)} top videos. Validating and seeding...")

    for vid in videos:
        # Check if video is available to play
        video_id = vid["video_id"]
        if not is_youtube_video_available(video_id):
            print(f"[Seeder] YouTube video {video_id} is unavailable (removed/private). Skipping.")
            continue

        title = vid["title"]
        if len(title.strip()) < 10:
            title = f"Vlog Trip: {title}"
            
        loc = map_location_for_text(title + " " + vid["description"])
        if not loc:
            loc = LOCATIONS[1] # Cox's Bazar fallback
            
        pin_id = loc["pinId"]
        enrich = ENRICHMENT_DATA.get(pin_id, ENRICHMENT_DATA["pin_coxsbazar"])
        
        trip_id = f"trip_yt_{vid['video_id']}"
        author_id = f"author_{vid['channel'].lower().replace(' ', '_')}"
        video_url = vid["url"] or f"https://www.youtube.com/watch?v={vid['video_id']}"
        thumbnail_url = vid["thumbnail_path"] or f"https://img.youtube.com/vi/{vid['video_id']}/0.jpg"
        
        # Build High-Quality TripLog blocks
        blocks = [
            {
                "id": "block_text_0",
                "content": f"YouTube Video Vlog by {vid['channel']}. {vid['description'][:300]}...",
                "isBold": True,
                "runtimeType": "text"
            },
            {
                "id": "block_text_1",
                "content": enrich["default_desc"],
                "isBold": False,
                "runtimeType": "text"
            },
            # 1. Video block of actual video
            {
                "id": "block_video_0",
                "storageUrl": video_url,
                "caption": title,
                "runtimeType": "video"
            },
            # 3. Cost Breakdown
            {
                "id": "block_cost_0",
                "items": enrich["cost_items"],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            # 4. Route
            {
                "id": "block_route_0",
                "points": enrich["route"]["points"],
                "description": enrich["route"]["description"],
                "runtimeType": "route"
            },
            # 5. Safety notes
            {
                "id": "block_safety_0",
                "text": enrich["safety_notes"][0]["text"],
                "level": enrich["safety_notes"][0]["level"],
                "runtimeType": "safetyNote"
            }
        ]

        published_dt = parse_date(vid["published_at"])
        delta = now - published_dt
        collection_name = 'archived_trip_logs' if delta.days > 365 else 'trip_logs'

        trip_ref = db.collection(collection_name).document(trip_id)
        trip_ref.set({
            "tripId": trip_id,
            "authorId": author_id,
            "title": title,
            "blocks": blocks,
            "routePoints": enrich["route"]["points"],
            "costItems": enrich["cost_items"],
            "locationPinId": pin_id,
            "trustScore": random.randint(90, 150),
            "helpfulVotes": int(clean_none(vid["view_count"], 0) / 2000) + random.randint(15, 50),
            "lastConfirmed": firestore.SERVER_TIMESTAMP,
            "division": loc["division"],
            "district": loc["district"],
            "hidden": False,
            "tier": "verified",
            "syncStatus": "synced",
            "isPremiumGuide": False,
            "publishedAt": published_dt
        })
        linked_trips[pin_id].append(trip_id)
        trip_count += 1

    # 5. Update Location Pins with their linked IDs
    print("[Seeder] Updating location pins with linked IDs...")
    for loc in LOCATIONS:
        pin_ref = db.collection('location_pins').document(loc["pinId"])
        pin_ref.update({
            "linkedTripIds": linked_trips[loc["pinId"]][:10], # Keep top 10
            "linkedTipIds": linked_tips[loc["pinId"]][:10]
        })

    conn.close()
    print(f"\n[Seeder] Seeding finished successfully!")
    print(f"[Seeder] Total TripLogs created: {trip_count}")
    print(f"[Seeder] Total ProTips created: {len(CURATED_PRO_TIPS)}")

if __name__ == "__main__":
    seed_database()
