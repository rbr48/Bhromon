import sqlite3
conn = sqlite3.connect('travel_data.db')
c = conn.cursor()
c.execute("SELECT url, status, message FROM crawl_log")
rows = c.fetchall()
oks = [r for r in rows if r[1] == 'ok']
skips = [r for r in rows if r[1] == 'skip']
errors = [r for r in rows if r[1] == 'error']
print(f"OKs: {len(oks)}, Skips: {len(skips)}, Errors: {len(errors)}")

c.execute("SELECT COUNT(*) FROM articles")
print(f"Articles in DB: {c.fetchone()[0]}")

c.execute("SELECT COUNT(*) FROM videos")
print(f"Videos in DB: {c.fetchone()[0]}")

c.execute("SELECT COUNT(*) FROM facebook_posts")
print(f"Facebook Posts in DB: {c.fetchone()[0]}")

