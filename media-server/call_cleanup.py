"""Removes old call records.

A call document keeps both sides' session descriptions, and its candidate
subcollections keep their network addresses. Nothing needs them once a call is
over: the chat keeps its own call log. They are removed after CALL_RETENTION, in
the same daily run as the story cleanup.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

logger = logging.getLogger("bhromon.call_cleanup")

CALL_RETENTION = timedelta(days=30)
BATCH_SIZE = 200
MAX_BATCHES_PER_RUN = 25


def delete_with_children(db: Any, ref: Any) -> None:
    """Deletes a document and everything under it."""
    recursive = getattr(db, "recursive_delete", None)
    if callable(recursive):
        recursive(ref)
        return
    for child in ref.collections():
        for doc in child.stream():
            doc.reference.delete()
    ref.delete()


def run_call_cleanup(
    db: Any,
    now: datetime,
    *,
    batch: int = BATCH_SIZE,
    max_batches: int = MAX_BATCHES_PER_RUN,
) -> Dict[str, int]:
    """Deletes calls created more than CALL_RETENTION ago, `batch` at a time."""
    now_utc = now.astimezone(timezone.utc) if now.tzinfo else now.replace(tzinfo=timezone.utc)
    threshold = now_utc - CALL_RETENTION
    stats = {"deleted": 0, "errors": 0}
    for _ in range(max_batches):
        old = list(db.collection("calls").where("createdAt", "<", threshold).limit(batch).stream())
        for doc in old:
            try:
                delete_with_children(db, doc.reference)
                stats["deleted"] += 1
            except Exception as error:
                stats["errors"] += 1
                logger.error("Call cleanup failed for %s: %s", doc.reference.path, error)
        if len(old) < batch or stats["errors"]:
            break
    return stats
