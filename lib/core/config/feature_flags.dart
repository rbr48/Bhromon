// Compile-time feature switches. Each defaults to on. A build can turn one off
// with `--dart-define=NAME=false`.

/// The new groups experience: the groups list (the Groups tab), the group page
/// (`/group-hub?tourId=…`), the members sheet, and the profile's Games tab. With the
/// flag off, the app keeps the layout it has always had.
const bool kGroupsV2 = bool.fromEnvironment('GROUPS_V2', defaultValue: true);

/// The live journey: GPS tracking during a trip, destination notices, hub
/// alarms and the wake-up alarm at the destination. On by default. The remaining
/// gate is the 12-hour highway battery test on a device (ROADMAP.md, Sprint 9).
const bool kLiveJourney =
    bool.fromEnvironment('LIVE_JOURNEY', defaultValue: true);
