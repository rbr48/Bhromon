// Compile-time feature switches. Each is off unless it is passed with
// `--dart-define=NAME=true`. Release builds leave them off.

/// The new groups experience: the groups list (the Groups tab), the group page
/// (`/group-hub?tourId=…`), the members sheet, and the profile's Games tab. With the
/// flag off, the app keeps the layout it has always had.
const bool kGroupsV2 = bool.fromEnvironment('GROUPS_V2', defaultValue: true);

/// The live journey: GPS tracking during a trip, destination notices, hub
/// alarms and the wake-up alarm at the destination. Off until the device
/// acceptance tests in docs/roadmap pass, so release builds keep today's journey
/// screen.
const bool kLiveJourney =
    bool.fromEnvironment('LIVE_JOURNEY', defaultValue: true);
