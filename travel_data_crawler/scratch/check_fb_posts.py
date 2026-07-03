import sqlite3
import json
import sys

# Set output encoding to utf-8
sys.stdout.reconfigure(encoding='utf-8')

conn = sqlite3.connect('travel_data.db')
conn.row_factory = sqlite3.Row
posts = conn.execute("SELECT * FROM facebook_posts").fetchall()
print(f"Total posts in DB: {len(posts)}")
for i, p in enumerate(posts):
    print(f"\n--- Post {i+1} ---")
    print(f"Page: {p['page']}")
    print(f"ID: {p['post_id']}")
    print(f"Content length: {len(p['content'])}")
    print(f"Content: {p['content'][:300]}")
    print(f"Images: {p['images']}")
    print(f"Links: {p['links']}")
conn.close()
