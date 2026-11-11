"""Which groups have the SOS feature.

Only a trip, a household (a plain family circle with no preset), a mess and a housing society have it.
Every other group is off, and so is a preset this list does not name. The app
(TourGroup.supportsSafetyAlerts) and the rules (sosAllowedTour in firestore.rules) apply the same rule,
so keep the three in step.
"""

from typing import Any, Mapping

# The presets that keep SOS. A missing or empty preset is a trip or a household.
SOS_PRESETS = frozenset({"mess", "society"})


def sos_allowed(tour: Mapping[str, Any]) -> bool:
    """Whether a tour document has SOS."""
    preset = tour.get("preset")
    if preset is None or preset == "":
        return True
    return isinstance(preset, str) and preset in SOS_PRESETS
