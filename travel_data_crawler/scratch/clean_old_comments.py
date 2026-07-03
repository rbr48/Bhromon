import sqlite3

conn = sqlite3.connect('travel_data.db')
c = conn.cursor()

# Delete the two comment rows
ids_to_delete = ['ba23d19dfd33', '665dab6d5acd']
for post_id in ids_to_delete:
    c.execute("DELETE FROM facebook_posts WHERE post_id = ?", (post_id,))

print(f"Deleted {c.rowcount} comments from database.")
conn.commit()

# Print remaining Facebook posts count
c.execute("SELECT COUNT(*) FROM facebook_posts")
print(f"Remaining Facebook posts in DB: {c.fetchone()[0]}")
conn.close()
