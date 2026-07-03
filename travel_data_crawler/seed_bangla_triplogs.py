import os
import json
import random
from datetime import datetime, timezone
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

# ─── Explorer Profiles to Seed ───
EXPLORERS = [
    {
        "uid": "author_rashed_a",
        "displayName": "Rashed Ahmed",
        "explorerScore": {"value": 842, "tier": "pioneer"},
        "tier": "pioneer",
        "badges": ["★ Pioneer", "★ Verified"],
        "division": "Dhaka",
        "createdAt": "2024-06-25T12:00:00Z",
        "isPioneer": True,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Rashed",
        "bio": "Avid hill trekker and explorer who loves scaling the heights of Bangladesh."
    },
    {
        "uid": "author_nusrat_i",
        "displayName": "Nusrat Islam",
        "explorerScore": {"value": 621, "tier": "verified"},
        "tier": "verified",
        "badges": ["★ Verified"],
        "division": "Khulna",
        "createdAt": "2024-08-15T08:30:00Z",
        "isPioneer": False,
        "isRegionExpert": True,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Nusrat",
        "bio": "Sundarbans and mangrove forest enthusiast. Conservation worker."
    },
    {
        "uid": "author_tanvir_h",
        "displayName": "Tanvir Hasan",
        "explorerScore": {"value": 498, "tier": "community"},
        "tier": "community",
        "badges": ["✓ Community"],
        "division": "Sylhet",
        "createdAt": "2024-09-01T14:45:00Z",
        "isPioneer": False,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Tanvir",
        "bio": "Tea garden wanderer, landscape photographer and haor explorer."
    },
    {
        "uid": "author_mitu_k",
        "displayName": "Mitu Khan",
        "explorerScore": {"value": 387, "tier": "community"},
        "tier": "community",
        "badges": ["✓ Community"],
        "division": "Chittagong",
        "createdAt": "2025-02-12T10:15:00Z",
        "isPioneer": False,
        "isRegionExpert": False,
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Mitu",
        "bio": "Cox's Bazar beach lover, marine conservationist and local foodie."
    }
]

# ─── New Location Pin for Kuakata ───
KUAKATA_PIN = {
    "pinId": "pin_kuakata",
    "name": "Kuakata Sea Beach",
    "geoHash": "w38z",
    "lat": 21.8124,
    "lng": 90.1173,
    "trustTier": "verified",
    "division": "Barisal",
    "district": "Patuakhali",
    "createdByUid": "system",
    "imageUrl": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80",
    "category": "beach",
    "averageRating": 4.5,
    "visitCount": 120,
    "photos": ["https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80"]
}

# ─── Verified Trip Logs (Strictly Recent, Under 2 Years Old) ───
TRIP_LOGS = [
    {
        "tripId": "trip_sajek_guide_2025",
        "authorId": "author_rashed_a",
        "title": "সাজেক ভ্যালি ভ্রমণ গাইড ও বাজেট চাঁদের গাড়ি বিবরণ",
        "locationPinId": "pin_sajek",
        "division": "Chittagong",
        "district": "Rangamati",
        "publishedAt": "2025-10-12T08:00:00Z",
        "trustScore": 115,
        "helpfulVotes": 42,
        "routePoints": [
            {"latitude": 23.1192, "longitude": 91.9686},
            {"latitude": 23.2543, "longitude": 92.0654},
            {"latitude": 23.3817, "longitude": 92.2938}
        ],
        "costItems": [
            {"label": "ঢাকা-খাগড়াছড়ি এসি বাস টিকেট (শ্যামলী)", "amountBDT": 1500, "category": "transport"},
            {"label": "চাঁদের গাড়ি রিজার্ভ (২ দিন রাউন্ড ট্রিপ)", "amountBDT": 10000, "category": "transport"},
            {"label": "মেঘ মাচাং রিসোর্ট ভাড়া (১ রাত)", "amountBDT": 3500, "category": "accommodation"},
            {"label": "ব্যাম্বো চিকেন ডিনার ও পাহাড়ি খাবার", "amountBDT": 400, "category": "food"}
        ],
        "blocks": [
            {
                "id": "blk_sajek_txt_1",
                "content": "সাজেক ভ্যালি বাংলাদেশের সবচেয়ে আকর্ষণীয় পাহাড়ি এলাকাগুলোর একটি। সমুদ্রপৃষ্ঠ থেকে প্রায় ১৮০০ ফুট উপরে পাহাড়ের চূড়ায় অবস্থিত সাজেক থেকে সকালের মেঘের ভেলা উপভোগ করা জীবনের এক অনন্য অভিজ্ঞতা। চারদিকে পাহাড়ের ক্যানোপি আর মাঝখানে চলে যাওয়া পিচঢালা পাহাড়ি রাস্তা দেখতে অসামান্য লাগে।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_sajek_safety_1",
                "text": "দীঘিনালা থেকে সাজেক যাওয়ার রাস্তা বেশ পাহাড়ি এবং খাড়া। তাই সকাল ১০টা অথবা দুপুর ৩টার মিলিটারি এসকর্টের সাথে যেতে হবে। এসকর্ট টাইমিং মিস করলে ঐ দিন আর সাজেক যাওয়ার অনুমতি পাওয়া যাবে না।",
                "level": "warning",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_sajek_cost_1",
                "items": [
                    {"label": "ঢাকা-খাগড়াছড়ি এসি বাস টিকেট (শ্যামলী)", "amountBDT": 1500, "category": "transport"},
                    {"label": "চাঁদের গাড়ি রিজার্ভ (২ দিন রাউন্ড ট্রিপ)", "amountBDT": 10000, "category": "transport"},
                    {"label": "মেঘ মাচাং রিসোর্ট ভাড়া (১ রাত)", "amountBDT": 3500, "category": "accommodation"},
                    {"label": "ব্যাম্বো চিকেন ডিনার ও পাহাড়ি খাবার", "amountBDT": 400, "category": "food"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_sajek_route_1",
                "points": [
                    {"latitude": 23.1192, "longitude": 91.9686},
                    {"latitude": 23.2543, "longitude": 92.0654},
                    {"latitude": 23.3817, "longitude": 92.2938}
                ],
                "description": "খাগড়াছড়ি শাপলা চত্বর থেকে দীঘিনালা হয়ে বাঘাইহাট এবং সাজেক ভ্যালি পর্যন্ত চাঁদের গাড়ির রুট।",
                "runtimeType": "route"
            },
            {
                "id": "blk_sajek_txt_2",
                "content": "সাজেকে ঘুরে দেখার মতো অন্য দুটি প্রধান স্থান হলো রুইলুই পাড়া এবং কংলাক পাহাড়। কংলাক পাহাড়ের চূড়ায় লুসাই জনগোষ্ঠীর মানুষ বসবাস করেন এবং সেখান থেকে চারপাশের পাহাড়ি দৃশ্য অসামান্য লাগে। রুইলুই পাড়াতে সন্ধ্যার সময় বসলে হিমেল হাওয়া ও পাহাড়ি মানুষের জীবনযাত্রা খুব কাছ থেকে লক্ষ্য করা যায়।",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    },
    {
        "tripId": "trip_cox_marine_2025",
        "authorId": "author_mitu_k",
        "title": "কক্সবাজার মেরিন ড্রাইভ দিয়ে ইনানী ও হিমছড়ি ওয়ান ডে ট্যুর প্ল্যান",
        "locationPinId": "pin_coxsbazar",
        "division": "Chittagong",
        "district": "Cox's Bazar",
        "publishedAt": "2025-12-05T10:30:00Z",
        "trustScore": 98,
        "helpfulVotes": 27,
        "routePoints": [
            {"latitude": 21.4272, "longitude": 91.9701},
            {"latitude": 21.3533, "longitude": 91.9842},
            {"latitude": 21.1856, "longitude": 92.0722}
        ],
        "costItems": [
            {"label": "ঢাকা-কক্সবাজার নন-এসি বাস টিকেট", "amountBDT": 900, "category": "transport"},
            {"label": "মেরিন ড্রাইভ সিএনজি রিজার্ভ (সারাদিন)", "amountBDT": 1500, "category": "transport"},
            {"label": "হিমছড়ি ইকো পার্ক প্রবেশ টিকেট", "amountBDT": 50, "category": "general"},
            {"label": "কলাতলী বিচ রেস্টুরেন্টে সী-ফুড লাঞ্চ", "amountBDT": 600, "category": "food"}
        ],
        "blocks": [
            {
                "id": "blk_cox_txt_1",
                "content": "কক্সবাজার শুধু মূল বিচেই সীমাবদ্ধ নয়। আসল সৌন্দর্য লুকিয়ে আছে মেরিন ড্রাইভের পাশে। সকাল সকাল ইজি-বাইক বা সিএনজি ভাড়া নিয়ে বের হয়ে পড়লে হিমছড়ি পাহাড় ও ইনানী বিচের পাথুরে সৈকতের সৌন্দর্য একই দিনে উপভোগ করা যায়। একদিকে নীল সমুদ্র আর অন্যদিকে সুউচ্চ সবুজ পাহাড়ের মধ্য দিয়ে চলে যাওয়া মেরিন ড্রাইভের রাস্তাটি অত্যন্ত নান্দনিক।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_cox_safety_1",
                "text": "সমুদ্রে গোসল করার সময় অবশ্যই লাইফগার্ডের সতর্কবার্তা এবং লাল পতাকার দিকে নজর রাখুন। জোয়ার-ভাটার চার্ট দেখে পানিতে নামবেন; ভাটার সময় সমুদ্রে নামা অত্যন্ত বিপজ্জনক।",
                "level": "danger",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_cox_cost_1",
                "items": [
                    {"label": "ঢাকা-কক্সবাজার নন-এসি বাস টিকেট", "amountBDT": 900, "category": "transport"},
                    {"label": "মেরিন ড্রাইভ সিএনজি রিজার্ভ (সারাদিন)", "amountBDT": 1500, "category": "transport"},
                    {"label": "হিমছড়ি ইকো পার্ক প্রবেশ টিকেট", "amountBDT": 50, "category": "general"},
                    {"label": "কলাতলী বিচ রেস্টুরেন্টে সী-ফুড লাঞ্চ", "amountBDT": 600, "category": "food"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_cox_route_1",
                "points": [
                    {"latitude": 21.4272, "longitude": 91.9701},
                    {"latitude": 21.3533, "longitude": 91.9842},
                    {"latitude": 21.1856, "longitude": 92.0722}
                ],
                "description": "কলাতলী মোড় থেকে শুরু হয়ে হিমছড়ি জলপ্রপাত ও পাহাড় পেরিয়ে পাথুরে ইনানী সৈকত পর্যন্ত মেরিন ড্রাইভের রুট।",
                "runtimeType": "route"
            },
            {
                "id": "blk_cox_txt_2",
                "content": "ইনানী সৈকতে অনেক বড় পাথরের দেখা মেলে যা জোয়ারের সময় পানিতে তলিয়ে যায় এবং ভাটায় জেগে ওঠে। এখানকার পানি মূল বিচের চেয়ে অনেক বেশি পরিষ্কার। তবে পাথরগুলোর উপর দিয়ে হাঁটার সময় সতর্ক থাকবেন, শেওলা জমে পিচ্ছিল হয়ে থাকে।",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    },
    {
        "tripId": "trip_sundarban_cruise_2024",
        "authorId": "author_nusrat_i",
        "title": "সুন্দরবন ও করমজল-হাড়বাড়িয়া ৩ দিন ২ রাতের লঞ্চ ট্যুর",
        "locationPinId": "pin_sundarbans",
        "division": "Khulna",
        "district": "Khulna",
        "publishedAt": "2024-09-15T07:30:00Z",
        "trustScore": 120,
        "helpfulVotes": 55,
        "routePoints": [
            {"latitude": 22.4842, "longitude": 89.6083},
            {"latitude": 22.2533, "longitude": 89.6324},
            {"latitude": 21.9497, "longitude": 89.1833}
        ],
        "costItems": [
            {"label": "সুন্দরবন ৩ দিন ২ রাত নন-এসি কেবিন লঞ্চ প্যাকেজ", "amountBDT": 12500, "category": "accommodation"},
            {"label": "বন বিভাগের প্রবেশ ফি ও সিকিউরিটি গার্ড চার্জ", "amountBDT": 1000, "category": "general"},
            {"label": "মংলা ঘাট থেকে খুলনা লোকাল বাস ভাড়া", "amountBDT": 150, "category": "transport"}
        ],
        "blocks": [
            {
                "id": "blk_sun_txt_1",
                "content": "পৃথিবীর বৃহত্তম ম্যানগ্রোভ বন সুন্দরবন ভ্রমণের সেরা উপায় হচ্ছে লঞ্চ ট্যুর। আমরা মংলা ঘাট থেকে তিন দিনের ট্যুরে রওনা দিয়েছিলাম এবং করমজল ও হাড়বাড়িয়ার ট্রেইলগুলোতে হেঁটে হরিণ ও বানরের সাথে বন্য পরিবেশ অনুভব করেছি। সুন্দরবনের নদী আর খালের বুক চিরে বয়ে চলা এক অসাধারণ রোমাঞ্চ।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_sun_safety_1",
                "text": "সুন্দরবনের গহীন বনে হাঁটার সময় সর্বদা সশস্ত্র বনরক্ষী বা গাইডের সাথে দলবদ্ধভাবে থাকুন। বাঘ, বন্য শুকর এবং কুমিরের উপস্থিতি রয়েছে। প্লাস্টিক বর্জ্য নদীতে ফেলবেন না।",
                "level": "danger",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_sun_cost_1",
                "items": [
                    {"label": "সুন্দরবন ৩ দিন ২ রাত নন-এসি কেবিন লঞ্চ প্যাকেজ", "amountBDT": 12500, "category": "accommodation"},
                    {"label": "বন বিভাগের প্রবেশ ফি ও সিকিউরিটি গার্ড চার্জ", "amountBDT": 1000, "category": "general"},
                    {"label": "মংলা ঘাট থেকে খুলনা লোকাল বাস ভাড়া", "amountBDT": 150, "category": "transport"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_sun_route_1",
                "points": [
                    {"latitude": 22.4842, "longitude": 89.6083},
                    {"latitude": 22.2533, "longitude": 89.6324},
                    {"latitude": 21.9497, "longitude": 89.1833}
                ],
                "description": "মংলা ঘাট থেকে পশুর নদী বেয়ে করমজল এবং হাড়বাড়িয়া ইকো ট্যুরিজম কেন্দ্র হয়ে কটকার গহীন অরণ্য পর্যন্ত。",
                "runtimeType": "route"
            },
            {
                "id": "blk_sun_txt_2",
                "content": "হাড়বাড়িয়াতে একটি সুন্দর কাঠের ফুট ট্রেইল আছে যা বনের মধ্য দিয়ে চলে গেছে। সেখানে নীরবতা বজায় রাখলে বন্য হরিণ এবং বিভিন্ন বিরল পাখির দেখা পাওয়ার সম্ভাবনা অনেক বেড়ে যায়। করমজলে নোনা পানির কুমির প্রজনন কেন্দ্রটিও বেশ শিক্ষণীয়。",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    },
    {
        "tripId": "trip_ratargul_swamp_2024",
        "authorId": "author_tanvir_h",
        "title": "রাতারগুল সোয়াম্প ফরেস্ট নৌকা ভ্রমণ ও বর্ষার অ্যাডভেঞ্চার",
        "locationPinId": "pin_ratargul",
        "division": "Sylhet",
        "district": "Sylhet",
        "publishedAt": "2024-07-20T09:00:00Z",
        "trustScore": 105,
        "helpfulVotes": 38,
        "routePoints": [
            {"latitude": 24.9034, "longitude": 91.8686},
            {"latitude": 24.9943, "longitude": 91.9164},
            {"latitude": 25.0064, "longitude": 91.9312}
        ],
        "costItems": [
            {"label": "সিলেট অম্বরখানা থেকে মটরঘাট সিএনজি ভাড়া (রাউন্ড ট্রিপ)", "amountBDT": 1000, "category": "transport"},
            {"label": "রাতারগুল ডিঙ্গি নৌকা ভাড়া (সমিতি নির্ধারিত)", "amountBDT": 800, "category": "transport"},
            {"label": "লাইফ জ্যাকেট ও ছাতা ভাড়া", "amountBDT": 50, "category": "general"}
        ],
        "blocks": [
            {
                "id": "blk_rat_txt_1",
                "content": "রাতারগুল হচ্ছে বাংলাদেশের একমাত্র মিঠাপানির সোয়াম্প ফরেস্ট। বর্ষাকালে যখন পুরো বন পানিতে ডুবে যায়, তখন ছোট নৌকায় করে বনের মাঝ দিয়ে ভেসে চলা এক অসাধারণ অনুভূতি দেয়। চারিদিকের করচ ও হিজল গাছের সবুজ ক্যানোপি এক মায়াবী ও রহস্যময় পরিবেশ তৈরি করে।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_rat_safety_1",
                "text": "বনের ভেতর গাছের ডালপালা নিচু হয়ে থাকে, অনেক সময় সাপের ভয় থাকে। তাই বোট চালানোর সময় ডালপালায় হাত দেওয়া বা জলমগ্ন গাছে ধরা থেকে বিরত থাকুন। লাইফ জ্যাকেট পরা বাধ্যতামূলক।",
                "level": "warning",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_rat_cost_1",
                "items": [
                    {"label": "সিলেট অম্বরখানা থেকে মটরঘাট সিএনজি ভাড়া (রাউন্ড ট্রিপ)", "amountBDT": 1000, "category": "transport"},
                    {"label": "রাতারগুল ডিঙ্গি নৌকা ভাড়া (সমিতি নির্ধারিত)", "amountBDT": 800, "category": "transport"},
                    {"label": "লাইফ জ্যাকেট ও ছাতা ভাড়া", "amountBDT": 50, "category": "general"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_rat_route_1",
                "points": [
                    {"latitude": 24.9034, "longitude": 91.8686},
                    {"latitude": 24.9943, "longitude": 91.9164},
                    {"latitude": 25.0064, "longitude": 91.9312}
                ],
                "description": "সিলেট শহর থেকে মটরঘাট হয়ে রাতারগুল ওয়াচটাওয়ার প্রবেশ ও নৌকা রুট।",
                "runtimeType": "route"
            },
            {
                "id": "blk_rat_txt_2",
                "content": "বনের ঠিক মাঝখানে একটি ওয়াচটাওয়ার আছে। সেখান থেকে পুরো রাতারগুল বনের বিস্তৃত সবুজ দৃশ্য এবং বনের মধ্য দিয়ে চলে যাওয়া আঁকাবাঁকা খালের রূপ দেখা যায়। বর্ষাকালে ওয়াচটাওয়ারের চারপাশের দৃশ্য সত্যিই অপার্থিব।",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    },
    {
        "tripId": "trip_bandarban_hills_2026",
        "authorId": "author_rashed_a",
        "title": "বান্দরবান নীলগিরি ও নীলাচল ট্যুর গাইড ও আর্মি চেকপোস্ট নিয়মাবলী",
        "locationPinId": "pin_bandarban",
        "division": "Chittagong",
        "district": "Bandarban",
        "publishedAt": "2026-03-10T14:00:00Z",
        "trustScore": 110,
        "helpfulVotes": 33,
        "routePoints": [
            {"latitude": 22.1953, "longitude": 92.2184},
            {"latitude": 22.0343, "longitude": 92.3562},
            {"latitude": 21.9543, "longitude": 92.5186}
        ],
        "costItems": [
            {"label": "ঢাকা থেকে বান্দরবান এসি বাস (শ্যামলী)", "amountBDT": 1400, "category": "transport"},
            {"label": "সারাদিনের চাঁদের গাড়ি ভাড়া (নীলগিরি-নীলাচল)", "amountBDT": 4500, "category": "transport"},
            {"label": "নীলগিরি প্রবেশ টিকেট", "amountBDT": 100, "category": "general"},
            {"label": "পাহাড়ি ব্যাম্বো চিকেন লাঞ্চ", "amountBDT": 350, "category": "food"}
        ],
        "blocks": [
            {
                "id": "blk_ban_txt_1",
                "content": "বান্দরবানের নীলগিরি এবং নীলাচল বাংলাদেশের অন্যতম চমৎকার দুটি পাহাড়ের চূড়া। নীলগিরিতে পাহাড় আর মেঘের মিলনমেলা দেখা যায়, আর নীলাচল থেকে বিকেলের সূর্যাস্ত এবং রাতের বান্দরবান শহরের অসামান্য ভিউ পাওয়া যায়। বান্দরবানের সর্পিল পাহাড়ি রাস্তা দিয়ে চিম্বুকের দিকে যাওয়া এক রোমাঞ্চকর জার্নি।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_ban_safety_1",
                "text": "পার্বত্য এলাকায় ভ্রমণের সময় সাথে অবশ্যই জাতীয় পরিচয়পত্র (NID) বা পাসপোর্টের কয়েক সেট ফটোকপি রাখবেন। আর্মি চেকপোস্টে নাম ও ঠিকানা এন্ট্রি করা বাধ্যতামূলক। পাহাড়ের খাড়া ঢালে নামার সময় সাবধান থাকুন।",
                "level": "warning",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_ban_cost_1",
                "items": [
                    {"label": "ঢাকা থেকে বান্দরবান এসি বাস (শ্যামলী)", "amountBDT": 1400, "category": "transport"},
                    {"label": "সারাদিনের চাঁদের গাড়ি ভাড়া (নীলগিরি-নীলাচল)", "amountBDT": 4500, "category": "transport"},
                    {"label": "নীলগিরি প্রবেশ টিকেট", "amountBDT": 100, "category": "general"},
                    {"label": "পাহাড়ি ব্যাম্বো চিকেন লাঞ্চ", "amountBDT": 350, "category": "food"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_ban_route_1",
                "points": [
                    {"latitude": 22.1953, "longitude": 92.2184},
                    {"latitude": 22.0343, "longitude": 92.3562},
                    {"latitude": 21.9543, "longitude": 92.5186}
                ],
                "description": "বান্দরবান শহর থেকে শুরু হয়ে চিম্বুক পাহাড় হয়ে নীলগিরি হিল রিসোর্ট ও ওয়াচটাওয়ার রুট।",
                "runtimeType": "route"
            },
            {
                "id": "blk_ban_txt_2",
                "content": "নীলগিরি রিসোর্টটি বাংলাদেশ আর্মি দ্বারা পরিচালিত এবং সমুদ্রপৃষ্ঠ থেকে প্রায় ২২০০ ফুট উপরে অবস্থিত। এখানে মেঘ ছুঁয়ে দেখা যায়। তবে মেঘ দেখার সেরা সময় হচ্ছে বর্ষা ও শরৎকাল। শীতকালে সাধারণ কুয়াশার দেখা মেলে।",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    },
    {
        "tripId": "trip_kuakata_beach_2025",
        "authorId": "author_mitu_k",
        "title": "কুয়াকাতা সূর্যোদয় ও সূর্যাস্ত দেখার পারফেক্ট ট্যুর প্ল্যান ও বাইক ট্রিপ",
        "locationPinId": "pin_kuakata",
        "division": "Barisal",
        "district": "Patuakhali",
        "publishedAt": "2025-08-25T16:45:00Z",
        "trustScore": 102,
        "helpfulVotes": 30,
        "routePoints": [
            {"latitude": 21.8512, "longitude": 90.1343},
            {"latitude": 21.8124, "longitude": 90.1173},
            {"latitude": 21.8023, "longitude": 90.1654}
        ],
        "costItems": [
            {"label": "ঢাকা থেকে কুয়াকাতা ডিরেক্ট এসি বাস (পদ্মা সেতু হয়ে)", "amountBDT": 1200, "category": "transport"},
            {"label": "কুয়াকাতা হোটেল সিকদার রিসোর্ট (১ রাত)", "amountBDT": 2500, "category": "accommodation"},
            {"label": "মোটরসাইকেলে সৈকত ও রাখাইন পল্লী ট্যুর (সারাদিন)", "amountBDT": 500, "category": "transport"},
            {"label": "বিচ সংলগ্ন ফ্রাই মার্কেটে কোরাল ও রূপচাঁদা ফ্রাই", "amountBDT": 400, "category": "food"}
        ],
        "blocks": [
            {
                "id": "blk_kua_txt_1",
                "content": "কুয়াকাতা, যা 'সাগরকন্যা' নামে পরিচিত, বাংলাদেশের অত্যন্ত অনন্য একটি সমুদ্র সৈকত। এটি দেশের একমাত্র সৈকত যেখান থেকে একই সাথে সূর্যোদয় ও সূর্যাস্ত অবলোকন করা যায়। পদ্মা সেতু চালু হওয়ার পর ঢাকা থেকে মাত্র ৬-৭ ঘন্টায় সরাসরি বাসে কুয়াকাতা পৌঁছানো সম্ভব।",
                "isBold": False,
                "runtimeType": "text"
            },
            {
                "id": "blk_kua_safety_1",
                "text": "রাখাইন পল্লী বা ধর্মীয় মন্দিরগুলোতে প্রবেশের সময় শালীন পোশাক পরিধান করুন এবং তাদের সংস্কৃতির প্রতি শ্রদ্ধা প্রদর্শন করুন। সৈকতে বাইক ট্যুর নেওয়ার আগে ভাড়া দরদাম করে নিন।",
                "level": "info",
                "runtimeType": "safetyNote"
            },
            {
                "id": "blk_kua_cost_1",
                "items": [
                    {"label": "ঢাকা থেকে কুয়াকাতা ডিরেক্ট এসি বাস (পদ্মা সেতু হয়ে)", "amountBDT": 1200, "category": "transport"},
                    {"label": "কুয়াকাতা হোটেল সিকদার রিসোর্ট (১ রাত)", "amountBDT": 2500, "category": "accommodation"},
                    {"label": "মোটরসাইকেলে সৈকত ও রাখাইন পল্লী ট্যুর (সারাদিন)", "amountBDT": 500, "category": "transport"},
                    {"label": "বিচ সংলগ্ন ফ্রাই মার্কেটে কোরাল ও রূপচাঁদা ফ্রাই", "amountBDT": 400, "category": "food"}
                ],
                "currency": "BDT",
                "runtimeType": "costEntry"
            },
            {
                "id": "blk_kua_route_1",
                "points": [
                    {"latitude": 21.8512, "longitude": 90.1343},
                    {"latitude": 21.8124, "longitude": 90.1173},
                    {"latitude": 21.8023, "longitude": 90.1654}
                ],
                "description": "কুয়াকাতা জিরো পয়েন্ট বিচ থেকে মোটরসাইকেলে গঙ্গামতির জঙ্গল এবং শুঁটকি পল্লী রুট।",
                "runtimeType": "route"
            },
            {
                "id": "blk_kua_txt_2",
                "content": "কুয়াকাতায় সূর্যোদয় দেখতে হলে ভোরে গঙ্গামতির চরে যেতে হবে, আর সূর্যাস্ত দেখতে হবে কুয়াকাতা প্রধান বিচে বা লেম্বুর চরে দাঁড়িয়ে। এখানকার ফ্রাই মার্কেটের তাজা সামুদ্রিক মাছের ফ্রাই অত্যন্ত সুস্বাদু ও সাশ্রয়ী।",
                "isBold": False,
                "runtimeType": "text"
            }
        ]
    }
]

def seed_database():
    db = get_firestore_client()
    print("[Seeder] Connected to Firestore successfully.")

    # 1. Seed/Update Explorer Profiles
    print("[Seeder] Uploading explorer profiles...")
    for exp in EXPLORERS:
        ref = db.collection('explorer_profiles').document(exp["uid"])
        ref.set(exp, merge=True)
        print(f"  + Seeded/Updated explorer profile: {exp['displayName']} ({exp['uid']})")

    # 2. Seed Location Pin for Kuakata if it doesn't exist
    print("[Seeder] Ensuring Kuakata Location Pin exists...")
    k_ref = db.collection('location_pins').document(KUAKATA_PIN["pinId"])
    k_ref.set(KUAKATA_PIN, merge=True)
    print("  + Seeded Kuakata Location Pin.")

    # Track linked IDs per pin to update locations collection later
    linked_trips = {
        "pin_sajek": [],
        "pin_coxsbazar": [],
        "pin_sundarbans": [],
        "pin_bandarban": [],
        "pin_sreemangal": [],
        "pin_ratargul": [],
        "pin_saintmartin": [],
        "pin_lalbagh": [],
        "pin_ahsanmanzil": [],
        "pin_shatgombuj": [],
        "pin_kuakata": []
    }

    # 3. Seed Trip Logs (with date partition by 365 days)
    now = datetime.now(timezone.utc)
    seeded_count = 0
    
    print("[Seeder] Uploading Bangla Trip Logs...")
    for trip in TRIP_LOGS:
        # Build Firestore friendly JSON
        pub_dt = datetime.fromisoformat(trip["publishedAt"].replace("Z", "+00:00"))
        
        # Partition logs based on 365 days
        delta = now - pub_dt
        collection_name = 'archived_trip_logs' if delta.days > 365 else 'trip_logs'
        
        trip_doc = {
            "tripId": trip["tripId"],
            "authorId": trip["authorId"],
            "title": trip["title"],
            "locationPinId": trip["locationPinId"],
            "division": trip["division"],
            "district": trip["district"],
            "publishedAt": pub_dt,
            "trustScore": trip["trustScore"],
            "helpfulVotes": trip["helpfulVotes"],
            "lastConfirmed": firestore.SERVER_TIMESTAMP,
            "routePoints": trip["routePoints"],
            "costItems": trip["costItems"],
            "blocks": trip["blocks"],
            "hidden": False,
            "tier": "verified",
            "syncStatus": "synced",
            "isPremiumGuide": False
        }
        
        trip_ref = db.collection(collection_name).document(trip["tripId"])
        trip_ref.set(trip_doc)
        print(f"  + Seeded TripLog {trip['tripId']} in collection '{collection_name}'")
        
        pin_id = trip["locationPinId"]
        if pin_id in linked_trips:
            linked_trips[pin_id].append(trip["tripId"])
            
        seeded_count += 1

    # 4. Update Location Pins with linked trip IDs (merge with existing linked IDs if any)
    print("[Seeder] Updating location pins with new linkedTripIds...")
    for pin_id, trip_ids in linked_trips.items():
        if not trip_ids:
            continue
        pin_ref = db.collection('location_pins').document(pin_id)
        pin_doc = pin_ref.get()
        if pin_doc.exists:
            data = pin_doc.to_dict()
            existing_trips = data.get("linkedTripIds", [])
            # Combine and deduplicate
            updated_trips = list(set(existing_trips + trip_ids))
            pin_ref.update({
                "linkedTripIds": updated_trips[:15] # limit to 15
            })
            print(f"  + Updated pin '{pin_id}' with linkedTripIds: {updated_trips}")

    print(f"\n[Seeder] Seeded {seeded_count} Bangla TripLogs successfully!")

if __name__ == "__main__":
    seed_database()
