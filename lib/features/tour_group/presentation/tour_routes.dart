/// The address of the Tours hub, opened on [tourId] when one is given.
///
/// The hub opens on the tour in its address ahead of the tour it remembers, so
/// a screen that belongs to a tour passes that tour when it leaves.
String tourHubPath([String? tourId]) {
  if (tourId == null || tourId.isEmpty) return '/group-hub';
  return '/group-hub?tourId=${Uri.encodeQueryComponent(tourId)}';
}
