"""Journey events are kept for thirty days, then deleted (roadmap LJ-4.6).

Each event is a member's arrival at, or departure from, a stop. The daily job
deletes the events older than the retention, in batches, the same way the call
records are cleaned (call_cleanup.py). Deleting a member's account removes that
member's events at once (functions/src/lib/accountErasure.ts).
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

logger = logging.getLogger("bhromon.journey_cleanup")

JOURNEY_EVENT_RETENTION = timedelta(days=30)
BATCH_SIZE = 200
MAX_BATCHES_PER_RUN = 25


def run_journey_event_cleanup(
    db: Any,
    now: datetime,
    *,
    batch: int = BATCH_SIZE,
    max_batches: int = MAX_BATCHES_PER_RUN,
) -> Dict[str, int]:
    """Deletes the journey events created more than the retention ago, `batch` at a time."""
    now_utc = now.astimezone(timezone.utc) if now.tzinfo else now.replace(tzinfo=timezone.utc)
    threshold = now_utc - JOURNEY_EVENT_RETENTION
    stats = {"deleted": 0, "errors": 0}
    for _ in range(max_batches):
        old = list(
            db.collection_group("journey_events")
            .where("createdAt", "<", threshold)
            .limit(batch)
            .stream()
        )
        for doc in old:
            try:
                doc.reference.delete()
                stats["deleted"] += 1
            except Exception as error:
                stats["errors"] += 1
                logger.error("Journey event cleanup failed for %s: %s", doc.reference.path, error)
        # Stop when the last batch was short, or when a delete failed: the same
        # documents would come back, so the run ends and the next run tries again.
        if len(old) < batch or stats["errors"]:
            break
    return stats
