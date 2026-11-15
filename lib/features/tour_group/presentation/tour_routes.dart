import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The address of the Tours hub, opened on [tourId] when one is given.
///
/// The hub opens on the tour in its address ahead of the tour it remembers, so
/// a screen that belongs to a tour passes that tour when it leaves.
String tourHubPath([String? tourId]) {
  if (tourId == null || tourId.isEmpty) return '/group-hub';
  return '/group-hub?tourId=${Uri.encodeQueryComponent(tourId)}';
}

/// Goes to [route] from the desktop sidebar or dock.
///
/// A page opened over a tool (a subject, a chapter, a quiz) is not one of the router's pages,
/// so the router would leave it on top and the tap would seem to do nothing. Those pages are
/// closed first.
void goFromShell(BuildContext context, String route) {
  Navigator.of(context).popUntil((r) => r.settings is Page);
  context.go(route);
}
