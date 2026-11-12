"""Keeps the in-app notification list for 90 days (users/{uid}/notifications).

The list is written by the media server (the pushes it keeps) and by the app (chat messages). The daily
run in main.py (04:00 Dhaka, with the other clean-ups) deletes the entries older than the retention window,
in batches, and at most MAX_PER_RUN in one run. A run that stops early leaves the rest for the next day,
because the same query finds them again.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

logger = logging.getLogger(__name__)

RETENTION_DAYS = 90
# Firestore allows 500 writes in one batch; this stays well under it.
BATCH_SIZE = 400
MAX_PER_RUN = 5000


def run_notification_retention(
    db: Any,
    now: datetime,
    *,
    retention_days: int = RETENTION_DAYS,
    limit: int = MAX_PER_RUN,
) -> Dict[str, int]:
    """Deletes the list entries older than `retention_days`. Returns how many were deleted and how many
    batches failed."""
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    cutoff = now - timedelta(days=retention_days)
    query = db.collection_group("notifications").where("timestamp", "<", cutoff).limit(limit)
    refs = [doc.reference for doc in query.stream()]
    deleted = 0
    errors = 0
    for start in range(0, len(refs), BATCH_SIZE):
        chunk = refs[start:start + BATCH_SIZE]
        batch = db.batch()
        for ref in chunk:
            batch.delete(ref)
        try:
            batch.commit()
            deleted += len(chunk)
        except Exception as error:  # One failed batch must not stop the others.
            errors += 1
            logger.error("Notification retention batch failed: %s", error)
    return {"deleted": deleted, "errors": errors}
