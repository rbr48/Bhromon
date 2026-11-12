"""Which groups keep the shared fund.

A trip, a household (a plain family circle with no preset), a mess, a housing society, a campus and the
school, sports, committee and friends circles keep it. An office, a samity and a study circle keep none,
and so does a preset this list does not name. The app (TourGroup.hasFund), the rules (fundAllowedTour in
firestore.rules) and this module apply the same rule, so keep the three in step.

A group with no fund gets no ledger push. Its money already recorded stays in the database.
"""

from typing import Any, Mapping

# The presets that keep the fund. A missing or empty preset is a trip or a household.
FUND_PRESETS = frozenset({"mess", "society", "campus", "school", "sports", "committee", "friends"})


def fund_allowed(tour: Mapping[str, Any]) -> bool:
    """Whether a tour document keeps the shared fund."""
    preset = tour.get("preset")
    if preset is None or preset == "":
        return True
    return isinstance(preset, str) and preset in FUND_PRESETS
