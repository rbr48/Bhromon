#!/usr/bin/env python3
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
"""
╔══════════════════════════════════════════════════════════════════╗
║         BHROMON TRAVEL DATA CRAWLER — MAIN RUNNER               ║
║  Collects: News · Blogs · YouTube · Facebook                    ║
║  Saves to: travel_data_crawler/data/  + SQLite DB               ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
    python main.py              # Full crawl (all sources)
    python main.py --news       # News only
    python main.py --blogs      # Blogs only
    python main.py --youtube    # YouTube only
    python main.py --facebook   # Facebook only (needs cookies)
    python main.py --stats      # Show DB stats only
    python main.py --export     # Export collected data to JSON/CSV/HTML
"""
import sys
import os
import argparse
import time
from datetime import datetime

# Add crawler dir to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from database import init_db, get_stats
from article_crawler import crawl_all_articles
from youtube_crawler import crawl_all_youtube
from facebook_crawler import crawl_all_facebook
from exporter import run_all_exports
from firestore_seeder import seed_database


def print_banner():
    print("""
╔══════════════════════════════════════════════════════════════════╗
║       ভ্রমণ  ·  BHROMON TRAVEL DATA CRAWLER                     ║
║       Bangladesh Travel Intelligence Platform                    ║
╠══════════════════════════════════════════════════════════════════╣
║  Sources:  Daily Star · bdnews24 · Prothom Alo · Kaler Kantho   ║
║            Jugantor · Sachalayatan · Somewhere in Blog           ║
║            Medium · Tripadvisor · YouTube · Facebook             ║
╚══════════════════════════════════════════════════════════════════╝
""")


def print_stats():
    stats = get_stats()
    print("\n┌─── DATABASE STATS ───────────────────────────┐")
    print(f"│  📰 Articles:       {stats['articles']:<6}                    │")
    print(f"│  🖼️  Images:         {stats['images']:<6}                    │")
    print(f"│  🎬 Videos:         {stats['videos']:<6}                    │")
    print(f"│  📘 Facebook Posts: {stats['facebook_posts']:<6}                    │")
    print(f"│  ❌ Errors:         {stats['errors']:<6}                    │")
    print("└──────────────────────────────────────────────┘\n")


def main():
    parser = argparse.ArgumentParser(description="Bhromon Travel Data Crawler")
    parser.add_argument("--news",     action="store_true", help="Crawl news sources only")
    parser.add_argument("--blogs",    action="store_true", help="Crawl blog sources only")
    parser.add_argument("--youtube",  action="store_true", help="Crawl YouTube only")
    parser.add_argument("--facebook", action="store_true", help="Crawl Facebook only")
    parser.add_argument("--export",   action="store_true", help="Export data to JSON/CSV/HTML")
    parser.add_argument("--stats",    action="store_true", help="Show database stats only")
    parser.add_argument("--seed",     action="store_true", help="Post/seed collected data to Firestore")
    args = parser.parse_args()

    print_banner()

    # Initialise database
    init_db()

    if args.stats:
        print_stats()
        return

    if args.export:
        run_all_exports()
        return

    if args.seed:
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  🚀  PHASE 5: POST/SEED TO FIRESTORE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        try:
            seed_database()
        except Exception as e:
            print(f"Error seeding database: {e}")
        return

    start_time = time.time()
    total_items = 0

    run_all = not any([args.news, args.blogs, args.youtube, args.facebook])

    if run_all or args.news or args.blogs:
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  RSS  PHASE 1: NEWS + BLOGS (RSS Feeds)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        n = crawl_all_articles()
        total_items += n
        print(f"\n  + Articles: {n} saved")
        print_stats()

    if run_all or args.youtube:
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  🎬  PHASE 3: YOUTUBE VIDEOS")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        n = crawl_all_youtube()
        total_items += n
        print(f"\n  ✓ YouTube: {n} videos saved")
        print_stats()

    if run_all or args.facebook:
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  📘  PHASE 4: FACEBOOK PAGES")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        n = crawl_all_facebook()
        total_items += n
        print(f"\n  ✓ Facebook: {n} posts saved")
        print_stats()

    # Auto-export after full run
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  📦  EXPORTING DATA")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    run_all_exports()

    # Auto-seed if credentials exist after full run
    if run_all:
        p = os.path.expanduser('~/.config/configstore/firebase-tools.json')
        if os.path.exists(p):
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("  🚀  AUTO-SEEDING TO FIRESTORE")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            try:
                seed_database()
            except Exception as e:
                print(f"Auto-seeding skipped/failed: {e}")

    elapsed = time.time() - start_time
    print(f"""
╔══════════════════════════════════════════════════════════════════╗
║  ✅  CRAWL COMPLETE                                              ║
║  Total items collected: {total_items:<6}                              ║
║  Time elapsed: {elapsed/60:.1f} minutes                                ║
║  Data saved in: travel_data_crawler/data/                        ║
║  Report at: travel_data_crawler/exports/report.html              ║
╚══════════════════════════════════════════════════════════════════╝
""")
    print_stats()


if __name__ == "__main__":
    main()
