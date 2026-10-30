"""Deletes the conversations and messages in the VPS chat database.

Run it on the server, against the database file, before the new media server
is deployed. Dry run by default: it counts what it would delete. Pass --apply to
delete it.

    python3 delete_chat_history.py --db /data/media-meta/bhromon_chat.db
    python3 delete_chat_history.py --db /data/media-meta/bhromon_chat.db --apply

--before-ms limits the delete to conversations created before that Unix time in
milliseconds. Device tokens are kept, so the same devices keep getting pushes.
"""

import argparse
import sqlite3
import sys


def _cutoff(before_ms):
    """The WHERE clause that picks conversations created before the cutoff, if any."""
    if before_ms is None:
        return "", ()
    return " WHERE created_at < ?", (before_ms,)


def plan(conn, before_ms):
    """The conversation ids and the message count a delete would remove."""
    where, args = _cutoff(before_ms)
    chat_ids = [row[0] for row in conn.execute(f"SELECT chat_id FROM conversations{where}", args)]
    messages = conn.execute(
        f"SELECT COUNT(*) FROM messages WHERE chat_id IN (SELECT chat_id FROM conversations{where})",
        args,
    ).fetchone()[0]
    return chat_ids, messages


def delete(conn, before_ms):
    """Deletes the messages first, then their conversations, in one transaction."""
    where, args = _cutoff(before_ms)
    with conn:
        conn.execute(
            f"DELETE FROM messages WHERE chat_id IN (SELECT chat_id FROM conversations{where})",
            args,
        )
        conn.execute(f"DELETE FROM conversations{where}", args)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Delete the VPS chat conversations and messages.")
    parser.add_argument("--db", required=True, help="Path to bhromon_chat.db")
    parser.add_argument("--before-ms", type=int, default=None, help="Only conversations created before this Unix time in ms")
    parser.add_argument("--apply", action="store_true", help="Delete. Without it, nothing is deleted.")
    args = parser.parse_args(argv)

    conn = sqlite3.connect(args.db)
    try:
        chat_ids, messages = plan(conn, args.before_ms)
        if not args.apply:
            print(f"Dry run: {len(chat_ids)} conversations and {messages} messages would be deleted. Add --apply to delete them.")
            return 0
        delete(conn, args.before_ms)
        print(f"Deleted {len(chat_ids)} conversations and {messages} messages.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
