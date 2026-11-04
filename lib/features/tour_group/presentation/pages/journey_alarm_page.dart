import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/journey_alarm_sound.dart';
import '../../domain/services/journey_alarm_ring.dart';

/// The full-screen wake-up alarm (roadmap LJ-3.4).
///
/// It starts [ring] and plays [sound] while it rings, and keeps the screen on.
/// The only ways to stop it are Dismiss, Snooze, and "I am awake". The back button
/// is blocked, so the alarm cannot be lost by accident.
class JourneyAlarmPage extends StatefulWidget {
  const JourneyAlarmPage({
    super.key,
    required this.title,
    required this.body,
    required this.ring,
    required this.sound,
    required this.onFinished,
    this.now = DateTime.now,
    this.tick = const Duration(seconds: 1),
  });

  /// The translated title and place line, given by the caller.
  final String title;
  final String body;

  final AlarmRing ring;
  final JourneyAlarmSound sound;

  /// Called once, with how the alarm ended. The caller closes the page.
  final ValueChanged<RingEnd> onFinished;

  /// The clock. Tests pass a fake one.
  final DateTime Function() now;

  /// How often the alarm checks the time.
  final Duration tick;

  @override
  State<JourneyAlarmPage> createState() => _JourneyAlarmPageState();
}

class _JourneyAlarmPageState extends State<JourneyAlarmPage> {
  Timer? _timer;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _apply(widget.ring.begin(widget.now()), rebuild: false);
    _timer = Timer.periodic(
      widget.tick,
      (_) => _apply(widget.ring.advance(widget.now())),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Runs the sound change, reports the end once, and rebuilds the buttons.
  void _apply(RingSound change, {bool rebuild = true}) {
    switch (change) {
      case RingSound.start:
        unawaited(widget.sound.start());
      case RingSound.stop:
        unawaited(widget.sound.stop());
      case RingSound.none:
        break;
    }
    final end = widget.ring.end;
    if (widget.ring.status == RingStatus.done && end != null && !_reported) {
      _reported = true;
      _timer?.cancel();
      widget.onFinished(end);
    }
    if (rebuild && mounted) setState(() {});
  }

  void _dismiss() => _apply(widget.ring.dismiss());

  void _awake() => _apply(widget.ring.imAwake());

  void _snooze() {
    final change = widget.ring.snooze(widget.now());
    if (change != null) _apply(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ring = widget.ring;
    final snoozesUsedUp =
        ring.snoozesUsed >= ring.maxSnoozes && ring.status != RingStatus.done;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1A12),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(
                  Icons.alarm_rounded,
                  size: 96,
                  color: AppColors.mintGreen,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: ring.status == RingStatus.done ? null : _dismiss,
                    child: Text(l10n.translate('alarm_dismiss')),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: ring.canSnooze ? _snooze : null,
                        child: Text(l10n.translate('alarm_snooze')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            ring.status == RingStatus.done ? null : _awake,
                        child: Text(l10n.translate('alarm_im_awake')),
                      ),
                    ),
                  ],
                ),
                if (snoozesUsedUp) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.translate('alarm_snooze_used_up'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
