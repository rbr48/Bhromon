import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/presentation/cubit/auth_cubit.dart';
import '../../auth/presentation/cubit/auth_state.dart';
import '../data/safety_alert_watcher.dart';
import '../data/tour_group_repository.dart';
import '../domain/services/incoming_safety_alerts.dart';

/// Shows a safety alert (SOS) another member raised, on whatever screen the app is on.
///
/// It sits above the navigator, like the share host, and listens while someone is signed
/// in. A new alert sounds once and stays as a red banner at the top until it is closed by
/// its sender or an admin, runs out of its six hours, or is dismissed on this device.
class SafetyAlertHost extends StatefulWidget {
  const SafetyAlertHost({
    super.key,
    required this.child,
    this.repository,
    this.onOpen,
    this.sound = true,
  });

  final Widget child;

  /// Lets tests supply a repository that does not touch Firebase.
  final TourGroupRepository? repository;

  /// Opens the group's safety screen. The app goes to its route; tests pass their own.
  final void Function(String tourId)? onOpen;

  /// Whether a new alert makes a sound. Tests turn it off.
  final bool sound;

  @override
  State<SafetyAlertHost> createState() => _SafetyAlertHostState();
}

class _SafetyAlertHostState extends State<SafetyAlertHost> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final SafetyAlertWatcher _watcher = SafetyAlertWatcher(_repository);

  final Set<String> _dismissed = <String>{};
  List<IncomingSafetyAlert> _shown = const [];
  Timer? _windowTimer;
  AudioPlayer? _player;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _watcher.alertsByTour.addListener(_refresh);
    _watcher.groupNames.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWithAuth(context.read<AuthCubit>().state);
    });
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    _watcher.alertsByTour.removeListener(_refresh);
    _watcher.groupNames.removeListener(_refresh);
    _watcher.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  /// Watches while someone is signed in, and forgets everything at sign-out.
  void _syncWithAuth(AuthState state) {
    final signedIn = state is Authenticated;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      _watcher.start();
    } else {
      _dismissed.clear();
      unawaited(_watcher.stop());
    }
  }

  void _refresh() {
    if (!mounted) return;
    final next = incomingSafetyAlerts(
      alertsByTour: _watcher.alertsByTour.value,
      groupNames: _watcher.groupNames.value,
      myEmail: _repository.currentEmail,
      now: DateTime.now(),
      dismissed: _dismissed,
    );
    final arrived = newlyArrivedAlerts(_shown, next);
    setState(() => _shown = next);
    if (arrived.isNotEmpty) _announce();
    // An open alert leaves the banner when its six hours run out, with no new answer from
    // the server, so the list is worked out again each minute while one is shown.
    _windowTimer?.cancel();
    _windowTimer =
        next.isEmpty ? null : Timer(const Duration(minutes: 1), _refresh);
  }

  /// Sounds and vibrates once for a new alert. A browser may refuse sound before the page
  /// has been touched; the banner is shown all the same.
  void _announce() {
    unawaited(HapticFeedback.heavyImpact());
    if (!widget.sound) return;
    final player = _player ??= AudioPlayer();
    unawaited(() async {
      try {
        await player.stop();
        await player.play(AssetSource('audio/ringtone_default.mp3'));
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }());
  }

  void _dismiss(IncomingSafetyAlert alert) {
    _dismissed.add(alert.key);
    unawaited(_player?.stop());
    _refresh();
  }

  void _open(IncomingSafetyAlert alert) {
    unawaited(_player?.stop());
    final open = widget.onOpen;
    if (open != null) {
      open(alert.tourId);
    } else {
      AppRouter.router.go('/group/${alert.tourId}/safety');
    }
    _dismiss(alert);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) => _syncWithAuth(state),
      child: Stack(
        children: [
          widget.child,
          if (_shown.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The newest two; more than that would cover the screen.
                        for (final alert in _shown.take(2))
                          _SafetyAlertBanner(
                            key: ValueKey<String>('sos_banner_${alert.key}'),
                            alert: alert,
                            onOpen: () => _open(alert),
                            onDismiss: () => _dismiss(alert),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SafetyAlertBanner extends StatelessWidget {
  const _SafetyAlertBanner({
    super.key,
    required this.alert,
    required this.onOpen,
    required this.onDismiss,
  });

  final IncomingSafetyAlert alert;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const red = Color(0xFFD32F2F);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Material(
          color: red,
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  const Icon(Icons.sos_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.translate('sos_banner_title',
                              args: {'name': alert.alert.senderName}),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.translate('sos_banner_group',
                              args: {'group': alert.groupName}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: red,
                      minimumSize: const Size(64, 48),
                    ),
                    child: Text(
                      l10n.translate('sos_banner_open'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.translate('sos_banner_dismiss'),
                    child: InkResponse(
                      onTap: onDismiss,
                      radius: 24,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
