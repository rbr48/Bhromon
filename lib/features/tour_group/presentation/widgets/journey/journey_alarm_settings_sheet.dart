import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../data/live_journey_session.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/hub_alert_engine.dart';
import '../../../domain/services/journey_targets.dart';
import '../../../domain/services/trip_alarm_plan.dart';

/// Opens the alarm settings (roadmap LJ-3.6) and saves what the user picks. The
/// settings apply to the running trip, and they are kept for the next one.
Future<void> showJourneyAlarmSettings(
  BuildContext context, {
  required LiveJourneySession session,
  required TourGroup group,
}) async {
  final targets = journeyTargetsFor(group);
  final result = await showModalBottomSheet<JourneyAlarmSettings>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: context.forest.sheet,
    builder: (_) => _JourneyAlarmSheet(
      initial: session.settings,
      targets: [
        ...targets.stops,
        if (targets.destination != null) targets.destination!,
      ],
    ),
  );
  if (result != null) await session.updateSettings(result);
}

/// How early the notices come, in metres, for stops and for the destination.
class _Preset {
  const _Preset(this.key, this.hubM, this.destinationM);

  final String key;
  final List<double> hubM;
  final List<double> destinationM;
}

const List<_Preset> _presets = [
  _Preset('journey_alarm_near', [2000, 500], [5000, 2000, 500]),
  _Preset('journey_alarm_normal', [5000, 1000], [10000, 3000, 1000]),
  _Preset('journey_alarm_far', [10000, 3000, 1000], [20000, 10000, 3000, 1000]),
];

/// The minutes before arrival that the time alarm can use.
const List<int> _etaLeads = [15, 25, 40];

class _JourneyAlarmSheet extends StatefulWidget {
  const _JourneyAlarmSheet({required this.initial, required this.targets});

  final JourneyAlarmSettings initial;
  final List<AlertTarget> targets;

  @override
  State<_JourneyAlarmSheet> createState() => _JourneyAlarmSheetState();
}

class _JourneyAlarmSheetState extends State<_JourneyAlarmSheet> {
  late JourneyAlarmSettings _s = widget.initial;

  bool _matches(_Preset p) =>
      listEquals(_s.hubApproachThresholdsM, p.hubM) &&
      listEquals(_s.finalApproachThresholdsM, p.destinationM);

  void _setMuted(String id, bool muted) {
    final ids = Set<String>.of(_s.mutedTargetIds);
    if (muted) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    setState(() => _s = _s.copyWith(mutedTargetIds: ids));
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) {
    final f = context.forest;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (on) => setState(() => onChanged(on)),
      title: Text(title, style: TextStyle(color: f.text, fontSize: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('journey_alarm_settings_title'),
              style: TextStyle(
                color: f.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('journey_alarm_note'),
              style: TextStyle(color: f.text54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _switch(
              l10n.translate('journey_alarm_hub_approach'),
              _s.hubApproach,
              (v) => _s = _s.copyWith(hubApproach: v),
            ),
            _switch(
              l10n.translate('journey_alarm_hub_arrive'),
              _s.hubArrive,
              (v) => _s = _s.copyWith(hubArrive: v),
            ),
            _switch(
              l10n.translate('journey_alarm_final_approach'),
              _s.finalApproach,
              (v) => _s = _s.copyWith(finalApproach: v),
            ),
            _switch(
              l10n.translate('journey_alarm_final_arrive'),
              _s.finalArrivalAlarm,
              (v) => _s = _s.copyWith(finalArrivalAlarm: v),
            ),
            _switch(
              l10n.translate('journey_alarm_overshoot'),
              _s.overshootAlarm,
              (v) => _s = _s.copyWith(overshootAlarm: v),
            ),
            _switch(
              l10n.translate('journey_alarm_eta'),
              _s.etaFallback,
              (v) => _s = _s.copyWith(etaFallback: v),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.translate('journey_alarm_threshold_title'),
              style: TextStyle(color: f.text70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text(l10n.translate(p.key)),
                    selected: _matches(p),
                    onSelected: (_) => setState(() {
                      _s = _s.copyWith(
                        hubApproachThresholdsM: p.hubM,
                        finalApproachThresholdsM: p.destinationM,
                      );
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('journey_alarm_eta_lead_title'),
              style: TextStyle(color: f.text70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final minutes in _etaLeads)
                  ChoiceChip(
                    label: Text(l10n.translate('journey_alarm_eta_lead',
                        args: {'min': l10n.number(minutes)})),
                    selected: _s.etaFallbackLead.inMinutes == minutes,
                    onSelected: (_) => setState(() {
                      _s = _s.copyWith(
                        etaFallbackLead: Duration(minutes: minutes),
                      );
                    }),
                  ),
              ],
            ),
            if (widget.targets.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final target in widget.targets)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !_s.mutedTargetIds.contains(target.id),
                  onChanged: (on) => _setMuted(target.id, !on),
                  title: Text(
                    l10n.translate('journey_alarm_stop_mute',
                        args: {'stop': target.name}),
                    style: TextStyle(color: f.text, fontSize: 14),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.translate('journey_alarm_cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _s),
                    child: Text(l10n.translate('journey_alarm_save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
