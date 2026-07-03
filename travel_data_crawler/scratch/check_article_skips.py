import sqlite3
import sys

sys.stdout.reconfigure(encoding='utf-8')

conn = sqlite3.connect('travel_data.db')
c = conn.cursor()

c.execute("SELECT source, url, status, message FROM crawl_log WHERE source != 'facebook' ORDER BY id DESC LIMIT 50")
rows = c.fetchall()
print(f"Last 50 Crawl Logs (excluding Facebook):")
for r in rows:
    print(f"Source: {r[0]} | URL: {r[1][:50]} | Status: {r[2]} | Message: {r[3]}")
conn.close()
