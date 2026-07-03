"""
Bhromon Travel Crawler — Configuration
RSS-first approach: reliable, no JavaScript required.
"""
import os

# ─── Base paths ────────────────────────────────────────────────────────────────
BASE_DIR      = os.path.dirname(os.path.abspath(__file__))
DATA_DIR      = os.path.join(BASE_DIR, "data")
ARTICLES_DIR  = os.path.join(DATA_DIR, "articles")
IMAGES_DIR    = os.path.join(DATA_DIR, "images")
VIDEOS_DIR    = os.path.join(DATA_DIR, "videos")
FACEBOOK_DIR  = os.path.join(DATA_DIR, "facebook")
NEWS_DIR      = os.path.join(DATA_DIR, "news")
BLOGS_DIR     = os.path.join(DATA_DIR, "blogs")
YOUTUBE_DIR   = os.path.join(DATA_DIR, "youtube")
LOGS_DIR      = os.path.join(BASE_DIR, "logs")
COOKIES_DIR   = os.path.join(BASE_DIR, "cookies")
EXPORTS_DIR   = os.path.join(BASE_DIR, "exports")
DB_PATH       = os.path.join(BASE_DIR, "travel_data.db")
FACEBOOK_COOKIES_FILE = os.path.join(COOKIES_DIR, "facebook_cookies.json")

# ─── Bangladesh travel keywords ────────────────────────────────────────────────
TRAVEL_KEYWORDS = [
    "Cox's Bazar", "Coxs Bazar", "Sundarbans", "Sundarban", "Sajek",
    "Bandarban", "Rangamati", "Sylhet", "Sreemangal", "Srimangal",
    "Jaflong", "Ratargul", "Kaptai", "Kuakata", "Saint Martin",
    "Nijhum Dwip", "Maheshkhali", "Madhabpur", "Lawachara",
    "Boga Lake", "Nafakhum", "Amiakhum", "Thanchi", "Remakri",
    "Birishiri", "Netrokona", "Modhupur", "Mainamati", "Paharpur",
    "Shat Gombuj", "Ahsan Manzil", "Lalbagh", "Bakerkhali",
    "Teknaf", "Naf River", "Chimbuk", "Nilgiri", "Keokradong",
    "Tajingdong", "Tahjindong", "Ruma", "Ali Kadam",
    # Generic
    "Bangladesh travel", "Bangladesh tourism", "Bangladesh tourist",
    "travel Bangladesh", "tour Bangladesh", "visit Bangladesh",
    "Bangladesh beach", "Bangladesh hill", "Bangladesh river",
    "Bangladesh waterfall", "Bangladesh forest", "Bangladesh adventure",
    "ভ্রমণ", "পর্যটন", "বেড়ানো", "হিল ট্র্যাক", "পাহাড়", "সমুদ্র সৈকত",
    "hill tracts", "bay of bengal", "mangrove", "tea garden", "haor",
    # General / informal / transliterated
    "tourist", "resort", "hotel", "waterfall", "nature", "trekking", 
    "vlog", "trip", "tour", "ট্যুর", "ট্যুরিস্ট", "রিসোর্ট", "হোটেল", 
    "ঝর্ণা", "প্রকৃতি", "মেঘ", "জলপ্রপাত", "ভ্রমণকারী", "ভ্রমণপিপাসু", 
    "ঘোরাঘুরি", "ভ্রমণসংক্রান্ত"
]

# ─── RSS FEEDS (primary — no JavaScript, very reliable) ───────────────────────
RSS_FEEDS = [
    # ── English News ──
    {
        "name": "Google News — Bangladesh Travel",
        "url": "https://news.google.com/rss/search?q=bangladesh+travel+tourism&hl=en-BD&gl=BD&ceid=BD:en",
        "type": "news", "language": "en",
    },
    {
        "name": "Google News — Cox Bazar",
        "url": "https://news.google.com/rss/search?q=cox+bazar+beach+bangladesh&hl=en-BD&gl=BD&ceid=BD:en",
        "type": "news", "language": "en",
    },
    {
        "name": "Google News — Sundarbans",
        "url": "https://news.google.com/rss/search?q=sundarbans+bangladesh+travel&hl=en-BD&gl=BD&ceid=BD:en",
        "type": "news", "language": "en",
    },
    {
        "name": "Google News — Bandarban Rangamati",
        "url": "https://news.google.com/rss/search?q=bandarban+rangamati+sajek+travel&hl=en-BD&gl=BD&ceid=BD:en",
        "type": "news", "language": "en",
    },
    {
        "name": "Google News — Sylhet Tourism",
        "url": "https://news.google.com/rss/search?q=sylhet+tourism+travel+bangladesh&hl=en-BD&gl=BD&ceid=BD:en",
        "type": "news", "language": "en",
    },
    {
        "name": "Daily Star",
        "url": "https://www.thedailystar.net/rss.xml",
        "type": "news", "language": "en",
    },
    {
        "name": "Daily Star Travel",
        "url": "https://www.thedailystar.net/travel/rss.xml",
        "type": "news", "language": "en",
    },
    {
        "name": "bdnews24 RSS",
        "url": "https://bdnews24.com/rss/feeds",
        "type": "news", "language": "en",
    },
    {
        "name": "The Business Standard",
        "url": "https://www.tbsnews.net/rss.xml",
        "type": "news", "language": "en",
    },
    {
        "name": "Dhaka Tribune Travel",
        "url": "https://www.dhakatribune.com/feeds/rss",
        "type": "news", "language": "en",
    },
    # ── Bangla News ──
    {
        "name": "Google News — বাংলাদেশ ভ্রমণ",
        "url": "https://news.google.com/rss/search?q=বাংলাদেশ+ভ্রমণ+পর্যটন&hl=bn&gl=BD&ceid=BD:bn",
        "type": "news", "language": "bn",
    },
    {
        "name": "Google News — কক্সবাজার ভ্রমণ",
        "url": "https://news.google.com/rss/search?q=কক্সবাজার+সুন্দরবন+বান্দরবান+ভ্রমণ&hl=bn&gl=BD&ceid=BD:bn",
        "type": "news", "language": "bn",
    },
    {
        "name": "Prothom Alo RSS",
        "url": "https://www.prothomalo.com/feed",
        "type": "news", "language": "bn",
    },
    {
        "name": "Prothom Alo Travel",
        "url": "https://www.prothomalo.com/lifestyle/travel/feed",
        "type": "news", "language": "bn",
    },
    {
        "name": "Jugantor RSS",
        "url": "https://www.jugantor.com/rss.xml",
        "type": "news", "language": "bn",
    },
    {
        "name": "Samakal RSS",
        "url": "https://samakal.com/rss.xml",
        "type": "news", "language": "bn",
    },
    {
        "name": "Ittefaq RSS",
        "url": "https://www.ittefaq.com.bd/rss.xml",
        "type": "news", "language": "bn",
    },
    {
        "name": "Manob Zamin RSS",
        "url": "https://mzamin.com/rss.xml",
        "type": "news", "language": "bn",
    },
    # ── Travel Blogs / Aggregators ──
    {
        "name": "Lonely Planet — Bangladesh",
        "url": "https://www.lonelyplanet.com/feeds/blog_posts.atom",
        "type": "blog", "language": "en",
    },
    {
        "name": "Travel Fish — Bangladesh",
        "url": "https://news.google.com/rss/search?q=bangladesh+site:travelfish.org&hl=en",
        "type": "blog", "language": "en",
    },
    {
        "name": "Medium Bangladesh Travel",
        "url": "https://news.google.com/rss/search?q=bangladesh+travel+blog+site:medium.com&hl=en",
        "type": "blog", "language": "en",
    },
    {
        "name": "Atlas Obscura Bangladesh",
        "url": "https://news.google.com/rss/search?q=bangladesh+site:atlasobscura.com&hl=en",
        "type": "blog", "language": "en",
    },
]

# ─── YouTube queries ───────────────────────────────────────────────────────────
YOUTUBE_QUERIES = [
    "Bangladesh travel vlog",
    "Cox Bazar beach Bangladesh 4K",
    "Sajek Valley travel guide",
    "Sundarban tour Bangladesh",
    "Bandarban travel vlog",
    "Sylhet tourist places",
    "Saint Martin Island Bangladesh",
    "Rangamati Lake tour",
    "Nafakhum waterfall Bangladesh",
    "Bangladesh hidden gems travel",
    "ভ্রমণ বাংলাদেশ vlog",
    "বাংলাদেশ পর্যটন ভিডিও",
    "Boga Lake Keokradong trek",
    "Kuakata beach Bangladesh",
    "Bangladesh adventure travel",
    "Haor Bangladesh travel",
    "Lawachara rainforest Bangladesh",
    "Chimbuk hill Bandarban",
    "Sundarbans mangrove forest tour",
]

YOUTUBE_CHANNELS = [
    "https://www.youtube.com/@TravelBD",
    "https://www.youtube.com/@BangladeshTourism",
]

# ─── Facebook public pages ─────────────────────────────────────────────────────
FACEBOOK_PAGES = [
    "https://www.facebook.com/TravelBangladesh",
    "https://www.facebook.com/visitbangladesh",
    "https://www.facebook.com/BangladeshTourismBoard",
    "https://www.facebook.com/TravellingBangladesh",
    "https://www.facebook.com/BangladeshAdventure",
    "https://www.facebook.com/explorebd",
    "https://www.facebook.com/bdtraveltips",
    "https://www.facebook.com/coxsbazarofficial",
    "https://www.facebook.com/travelersofbangladesh",
    "https://www.facebook.com/sajekvalleypage",
    "https://www.facebook.com/AmazingBangladesh",
    "https://www.facebook.com/BeautifulBangladesh",
]

# ─── Rate limiting ─────────────────────────────────────────────────────────────
RATE_LIMITS = {
    "request_delay_seconds": 1.5,
    "max_concurrent_requests": 3,
    "retry_attempts": 3,
    "retry_delay_seconds": 4,
    "timeout_seconds": 25,
    "max_image_size_mb": 15,
}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36",
]
