import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/services/battery_guidance.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../data/live_journey_session.dart';
import '../../../domain/services/live_journey_tracker.dart';

/// The live journey card at the top of the journey screen (roadmap LJ-2.3 and
/// LJ-5.1). It starts and ends a trip, holds the sharing switch, and shows where
/// the group is on the route. It rebuilds whenever the session changes.
class JourneyLiveCard extends StatelessWidget {
  const JourneyLiveCard({
    super.key,
    required this.session,
    required this.onStart,
    required this.onAlarmSettings,
  });

  final LiveJourneySession session;

  /// Starts a trip. The screen settles the permission first.
  final Future<void> Function() onStart;

  final VoidCallback onAlarmSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: f.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: f.accentText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('journey_live_title'),
                  style: TextStyle(
                    color: f.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!session.isTracking) ...[
            Text(
              l10n.translate('journey_live_idle'),
              style: TextStyle(color: f.text70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => unawaited(onStart()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.translate('journey_live_start')),
            ),
          ] else ...[
            Text(
              _status(context),
              style: TextStyle(color: f.text, fontSize: 14, height: 1.4),
            ),
            if (session.longStopPrompt) ...[
              const SizedBox(height: 10),
              _stillBanner(context),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: session.isSharing,
              onChanged: (on) => unawaited(session.setSharing(on: on)),
              title: Text(
                l10n.translate('journey_live_share'),
                style: TextStyle(color: f.text),
              ),
              subtitle: Text(
                l10n.translate('journey_live_share_hint'),
                style: TextStyle(color: f.text54, fontSize: 12),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAlarmSettings,
                    icon: const Icon(Icons.alarm_rounded),
                    label: Text(l10n.translate('journey_live_alarms')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _confirmEnd(context),
                    child: Text(l10n.translate('journey_live_end')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The status lines: the distance to the destination, the next stop, the
  /// arrival time and whether the group is still.
  String _status(BuildContext context) {
    final l10n = context.l10n;
    final targets = session.targets;
    if (targets.isEmpty) return l10n.translate('journey_live_no_route');
    final snap = session.snapshot;
    if (snap == null) return l10n.translate('journey_live_running');
    if (snap.status == JourneyStatus.offRoute) {
      return l10n.translate('journey_live_off_route');
    }
    final lines = <String>[];
    final destination = targets.destination;
    if (destination != null && snap.remainingM > 0) {
      final km = (snap.remainingM / 1000).round();
      lines.add(l10n.translate('journey_live_remaining', args: {
        'km': l10n.number(km),
        'place': destination.name,
      }));
    }
    final next = _nextStopName(snap);
    if (next != null) {
      lines.add(l10n.translate('journey_live_next', args: {'place': next}));
    }
    final eta = snap.etaToEnd;
    if (eta != null) {
      final time = localizedDateFormat('h:mm a').format(
        DateTime.now().add(eta),
      );
      lines.add(l10n.translate('journey_live_eta', args: {'time': time}));
    }
    if (snap.isStopped) lines.add(l10n.translate('journey_live_stopped'));
    if (lines.isEmpty) return l10n.translate('journey_live_running');
    return lines.join('\n');
  }

  /// The name of the stop the group is heading to, when the tracker names one.
  String? _nextStopName(JourneySnapshot snap) {
    final index = snap.nextVertex;
    final route = session.targets.route;
    if (index == null || route == null || index >= route.points.length) {
      return null;
    }
    final point = route.points[index];
    final targets = session.targets;
    for (final stop in [
      ...targets.stops,
      if (targets.destination != null) targets.destination!,
    ]) {
      if (stop.point == point) return stop.name;
    }
    return null;
  }

  Widget _stillBanner(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: f.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('journey_long_stop'),
            style: TextStyle(color: f.text, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: () => unawaited(BatteryGuidance.openSettings()),
                child: Text(l10n.translate('journey_long_stop_battery')),
              ),
              const Spacer(),
              TextButton(
                onPressed: session.dismissLongStopPrompt,
                child: Text(l10n.translate('journey_long_stop_keep')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.translate('journey_live_end_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.translate('journey_alarm_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.translate('journey_live_end')),
          ),
        ],
      ),
    );
    if (ok == true) await session.stop();
  }
}
