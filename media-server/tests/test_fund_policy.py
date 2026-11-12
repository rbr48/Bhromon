"""Which groups keep the shared fund on the VPS (fund_policy.py), and the tour lookup that applies it."""

from unittest.mock import MagicMock

import pytest

from fund_policy import FUND_PRESETS, fund_allowed
from notifications import NotificationEngine


@pytest.mark.parametrize(
    "tour",
    [
        {},
        {"preset": None},
        {"preset": ""},
        {"kind": "family"},
        {"preset": "mess"},
        {"preset": "society"},
        {"preset": "campus"},
        {"preset": "school"},
        {"preset": "sports"},
        {"preset": "committee"},
        {"preset": "friends"},
    ],
)
def test_groups_that_keep_the_fund(tour):
    assert fund_allowed(tour) is True


@pytest.mark.parametrize(
    "tour",
    [
        {"preset": "office"},
        {"preset": "samity"},
        {"preset": "study"},
        {"preset": "something-new"},
        {"preset": 7},
    ],
)
def test_groups_without_the_fund(tour):
    assert fund_allowed(tour) is False


def test_the_fund_presets_match_the_app():
    # TourGroup.hasFund in the app names the same presets.
    assert FUND_PRESETS == frozenset({"mess", "society", "campus", "school", "sports", "committee", "friends"})


def _engine_with_tour(exists, data):
    engine = NotificationEngine()
    snapshot = MagicMock()
    snapshot.exists = exists
    snapshot.to_dict.return_value = data
    db = MagicMock()
    db.collection.return_value.document.return_value.get.return_value = snapshot
    engine._get_db = MagicMock(return_value=db)
    return engine


def test_tour_lookup_applies_the_policy_to_the_stored_tour():
    assert _engine_with_tour(True, {"preset": "office"}).tour_allows_fund("t1") is False
    assert _engine_with_tour(True, {"preset": "mess"}).tour_allows_fund("t1") is True
    assert _engine_with_tour(True, {}).tour_allows_fund("t1") is True


def test_tour_lookup_keeps_no_fund_for_a_missing_tour():
    assert _engine_with_tour(False, None).tour_allows_fund("gone") is False
