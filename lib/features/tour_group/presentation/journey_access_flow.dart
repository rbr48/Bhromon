import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../domain/services/journey_access_policy.dart';
import 'live_journey_runtime.dart';

/// What the location permission allows a journey to do.
enum JourneyAccessResult {
  /// Tracking can run in the background.
  ready,

  /// Only while the app is open. The user declined background access.
  whileInUseOnly,

  /// No location, so the journey cannot start.
  refused,
}

LocationAccess _accessOf(LocationPermission permission) => switch (permission) {
      LocationPermission.always => LocationAccess.always,
      LocationPermission.whileInUse => LocationAccess.whileInUse,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied => LocationAccess.denied,
      LocationPermission.unableToDetermine => LocationAccess.notDetermined,
    };

bool _hasWhileInUse(LocationPermission permission) =>
    permission == LocationPermission.whileInUse ||
    permission == LocationPermission.always;

/// Settles the location permission before a journey starts (roadmap LJ-2.2).
///
/// The app asks for "while in use" first. The in-app disclosure comes before the
/// "all the time" prompt, and it is shown once. When the user declines background
/// access, the journey still runs while the app is open.
Future<JourneyAccessResult> ensureJourneyAccess(BuildContext context) async {
  final session = await LiveJourneyRuntime.instance.session();
  // Each step moves the flow on. The cap stops a loop if the system keeps
  // returning the same answer.
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!context.mounted) return JourneyAccessResult.refused;
    final permission = await Geolocator.checkPermission();
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    final step = nextLocationStep(
      access: _accessOf(permission),
      serviceEnabled: serviceOn,
      needsBackground: true,
      disclosureAccepted: session.store.readDisclosureSeen(),
    );
    switch (step) {
      case LocationStep.ready:
        return JourneyAccessResult.ready;
      case LocationStep.turnOnService:
        await Geolocator.openLocationSettings();
        if (context.mounted) {
          _say(context, context.l10n.translate('journey_access_off'));
        }
        return JourneyAccessResult.refused;
      case LocationStep.openSettings:
        await Geolocator.openAppSettings();
        if (context.mounted) {
          _say(context, context.l10n.translate('journey_access_refused'));
        }
        return JourneyAccessResult.refused;
      case LocationStep.askWhileInUse:
        final answer = await Geolocator.requestPermission();
        if (!_hasWhileInUse(answer)) return JourneyAccessResult.refused;
        break;
      case LocationStep.showDisclosure:
        if (!context.mounted) return JourneyAccessResult.refused;
        final accepted = await _showDisclosure(context);
        if (accepted != true) {
          return _hasWhileInUse(permission)
              ? JourneyAccessResult.whileInUseOnly
              : JourneyAccessResult.refused;
        }
        await session.store.saveDisclosureSeen();
        break;
      case LocationStep.askAlways:
        final answer = await Geolocator.requestPermission();
        if (answer == LocationPermission.always) {
          return JourneyAccessResult.ready;
        }
        return _hasWhileInUse(answer)
            ? JourneyAccessResult.whileInUseOnly
            : JourneyAccessResult.refused;
    }
  }
  return JourneyAccessResult.refused;
}

void _say(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
}

/// The disclosure, shown before the "all the time" prompt. Returns true when the
/// user continues.
Future<bool?> _showDisclosure(BuildContext context) {
  final l10n = context.l10n;
  final f = context.forest;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: f.sheet,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('journey_disclosure_title'),
              style: TextStyle(
                color: f.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('journey_disclosure_body'),
              style: TextStyle(color: f.text70, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(l10n.translate('journey_disclosure_later')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(l10n.translate('journey_disclosure_allow')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
