import sqlite3
import sys

sys.stdout.reconfigure(encoding='utf-8')

conn = sqlite3.connect('travel_data.db')
c = conn.cursor()

c.execute("SELECT DISTINCT source FROM crawl_log")
sources = [r[0] for r in c.fetchall()]
print(f"All log sources: {sources}")

c.execute("SELECT source, COUNT(*), status FROM crawl_log GROUP BY source, status")
print("\nLog counts by source and status:")
for r in c.fetchall():
    print(f"Source: {r[0]} | Count: {r[1]} | Status: {r[2]}")

c.execute("SELECT source, url, status, message FROM crawl_log WHERE source NOT LIKE 'youtube%' AND source != 'facebook' ORDER BY id DESC LIMIT 50")
rows = c.fetchall()
print(f"\nNon-YouTube, Non-Facebook Logs:")
for r in rows:
    print(f"Source: {r[0]} | URL: {r[1][:50]} | Status: {r[2]} | Message: {r[3]}")
conn.close()
