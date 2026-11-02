"""Tests for the daily removal of old call records."""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import call_cleanup


def _db_with(old_docs):
    db = MagicMock()
    query = db.collection.return_value.where.return_value.limit.return_value
    pages = [old_docs, []]
    query.stream.side_effect = lambda: iter(pages.pop(0) if pages else [])
    return db


def test_old_calls_are_deleted_with_their_candidates():
    docs = [MagicMock(), MagicMock()]
    db = _db_with(docs)
    now = datetime(2026, 3, 1, tzinfo=timezone.utc)

    stats = call_cleanup.run_call_cleanup(db, now, batch=10)

    assert stats == {"deleted": 2, "errors": 0}
    db.collection.assert_called_with("calls")
    field, op, threshold = db.collection.return_value.where.call_args.args
    assert (field, op) == ("createdAt", "<")
    assert threshold == now - timedelta(days=30)
    # recursive_delete removes the candidate subcollections with the call.
    assert db.recursive_delete.call_count == 2


def test_a_failed_delete_is_counted_and_stops_the_run():
    docs = [MagicMock(), MagicMock()]
    db = _db_with(docs)
    db.recursive_delete.side_effect = RuntimeError("boom")

    stats = call_cleanup.run_call_cleanup(db, datetime(2026, 3, 1, tzinfo=timezone.utc), batch=2)

    assert stats["errors"] == 2
    assert stats["deleted"] == 0
