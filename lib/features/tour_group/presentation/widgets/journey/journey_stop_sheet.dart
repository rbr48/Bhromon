import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../data/live_journey_session.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/services/journey_geometry.dart';
import '../../../domain/services/route_engine.dart';

/// The sheet of one stop on the journey (roadmap LJ-5.4): its distance and arrival
/// time, the places on the way to it, its notices, and whether its alarm is set.
class JourneyStopSheet extends StatelessWidget {
  const JourneyStopSheet({
    super.key,
    required this.stop,
    required this.incoming,
    required this.checkpoints,
    required this.notices,
    required this.livePoint,
    required this.session,
  });

  final RoutePoint stop;

  /// The leg that ends at this stop, if any.
  final RouteLeg? incoming;

  final List<RouteCheckpoint> checkpoints;
  final Stream<List<TourNotice>> notices;

  /// The group's last reading, when the trip runs.
  final GeoPoint? livePoint;

  /// The live session, when the journey feature is on.
  final LiveJourneySession? session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    final onWay = [
      for (final c in checkpoints)
        if (incoming != null && c.legKey == incoming!.key) c,
    ];
    final live = livePoint;
    final eta = incoming?.eta;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stop.name,
              style: TextStyle(
                color: f.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (live != null && stop.hasLocation)
              Text(
                l10n.translate('journey_stop_distance', args: {
                  'km': l10n.number(
                    (distanceM(live, GeoPoint(stop.lat!, stop.lng!)) / 1000)
                        .round(),
                  ),
                }),
                style: TextStyle(color: f.text70, fontSize: 14),
              ),
            if (eta != null)
              Text(
                l10n.translate('journey_live_eta', args: {
                  'time': localizedDateFormat('h:mm a').format(eta),
                }),
                style: TextStyle(color: f.text70, fontSize: 14),
              ),
            if (onWay.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                l10n.translate('journey_stop_checkpoints'),
                style: TextStyle(
                  color: f.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final c in onWay.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• ${c.name}',
                      style: TextStyle(color: f.text70, fontSize: 13)),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              l10n.translate('journey_stop_notices'),
              style: TextStyle(color: f.text, fontWeight: FontWeight.w600),
            ),
            StreamBuilder<List<TourNotice>>(
              stream: notices,
              builder: (context, snapshot) {
                final mine = [
                  for (final n in snapshot.data ?? const <TourNotice>[])
                    if (n.stopId == stop.id) n,
                ];
                if (mine.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.translate('journey_stop_no_notices'),
                      style: TextStyle(color: f.text54, fontSize: 13),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in mine.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${n.title}',
                            style: TextStyle(color: f.text70, fontSize: 13)),
                      ),
                  ],
                );
              },
            ),
            if (session != null) ...[
              const Divider(height: 24),
              ListenableBuilder(
                listenable: session!,
                builder: (context, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !session!.settings.mutedTargetIds.contains(stop.id),
                  onChanged: (on) => unawaited(_setAlarm(session!, on)),
                  title: Text(
                    l10n.translate('journey_stop_alarm'),
                    style: TextStyle(color: f.text),
                  ),
                  subtitle: Text(
                    l10n.translate('journey_stop_alarm_hint'),
                    style: TextStyle(color: f.text54, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setAlarm(LiveJourneySession s, bool on) {
    final ids = Set<String>.of(s.settings.mutedTargetIds);
    if (on) {
      ids.remove(stop.id);
    } else {
      ids.add(stop.id);
    }
    return s.updateSettings(s.settings.copyWith(mutedTargetIds: ids));
  }
}
