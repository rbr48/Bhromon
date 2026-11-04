import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/hub_alert_engine.dart';
import '../domain/services/journey_access_policy.dart';
import '../domain/services/journey_alert_presentation.dart';
import '../domain/services/journey_targets.dart';
import '../domain/services/journey_trip.dart';
import '../domain/services/live_journey_tracker.dart';
import '../domain/services/trip_alarm_plan.dart';
import 'journey_alarm_scheduler.dart';
import 'journey_prefs_store.dart';

/// The readings for one sampling plan, with the notification text for the
/// Android foreground service. The app passes the platform source; tests pass a
/// fake.
typedef JourneyFixesFactory = Stream<JourneyFix> Function(
  SamplingPlan sampling,
  String notificationTitle,
  String notificationText,
);

/// The text of the Android foreground-service notification, in both states. It
/// must say when the group can see the position (rule 2).
class JourneyServiceCopy {
  const JourneyServiceCopy({
    required this.title,
    required this.tracking,
    required this.sharing,
  });

  final String title;
  final String tracking;
  final String sharing;
}

/// Shows a notice now: an approach or arrival at a stop, or a ringing alarm.
abstract class JourneyNoticePort {
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required JourneyChannel channel,
    required bool rings,
    required String payload,
  });
}

/// An arrival at, or a departure from, a stop (roadmap LJ-4.2).
enum JourneyEventType { arrive, depart }

/// Records group events. Only called while sharing is on (rule 10).
abstract class JourneyEventSink {
  Future<void> record({
    required String tourId,
    required String stopId,
    required JourneyEventType type,
  });
}

/// Runs one live journey: the trip, the GPS readings, the stop notices, the
/// wake-up alarms and the group events (roadmap phases 2 and 3).
///
/// The session holds no plugin. The app wires the platform ports in, and the
/// tests use fakes with a fixed clock. Tracking runs only while a trip runs
/// (rule 1).
class LiveJourneySession extends ChangeNotifier {
  LiveJourneySession({
    required this.store,
    required this.fixes,
    required this.scheduler,
    required this.notices,
    required this.events,
    required this.text,
    required this.formatNumber,
    required this.onRing,
    DateTime Function()? now,
    JourneyTripLifecycle? lifecycle,
    this.idleCheckEvery = const Duration(minutes: 5),
    this.persistEvery = const Duration(minutes: 1),
  })  : _now = now ?? DateTime.now,
        _lifecycle = lifecycle ?? JourneyTripLifecycle();

  final JourneyPrefsStore store;
  final JourneyFixesFactory fixes;
  final JourneyAlarmScheduler scheduler;
  final JourneyNoticePort notices;
  final JourneyEventSink events;

  /// Translates a presentation text.
  final String Function(JourneyText) text;

  /// Formats a number in the user's numerals.
  final String Function(num value) formatNumber;

  /// Asks the app to show the full-screen alarm for [ring].
  final void Function(JourneyPresentation ring) onRing;

  final DateTime Function() _now;
  final JourneyTripLifecycle _lifecycle;
  final Duration idleCheckEvery;
  final Duration persistEvery;

  TourGroup? _group;
  JourneyAlarmSettings _settings = const JourneyAlarmSettings();
  JourneyTargets _targets = JourneyTargets.none;
  JourneyTracker? _tracker;
  HubAlertEngine? _engine;
  StationaryDetector _still = StationaryDetector();
  SamplingPlan _sampling = SamplingPlan.moving;
  StreamSubscription<JourneyFix>? _sub;
  Timer? _idleTimer;
  JourneyServiceCopy? _copy;
  DateTime? _plannedFinalEta;
  JourneySnapshot? _snapshot;
  bool _longStop = false;
  bool _longStopPromptOpen = false;
  Set<String> _arrivedNow = {};
  Set<String> _everArrived = {};
  DateTime? _lastPersistAt;
  bool _disposed = false;
  final StreamController<JourneyFix> _readings =
      StreamController<JourneyFix>.broadcast();

  /// The readings the tracker has taken, for the journey screen's live position
  /// while a trip runs. Readings the tracker rejects are not sent.
  Stream<JourneyFix> get readings => _readings.stream;

  /// The running trip, or null.
  JourneyTrip? get trip => _lifecycle.active;

  bool get isTracking => trip != null;

  /// Whether the group can see this device's position (rule 2).
  bool get isSharing => trip?.sharing ?? false;

  /// The latest reading, as the tracker reads it.
  JourneySnapshot? get snapshot => _snapshot;

  JourneyAlarmSettings get settings => _settings;

  /// The targets of the running trip.
  JourneyTargets get targets => _targets;

  /// The device has been still for a long stop. Tracking then samples less.
  bool get isLongStop => _longStop;

  /// Asks the user whether tracking should stay on (roadmap LJ-2.4). Shown once
  /// for each long stop.
  bool get longStopPrompt => _longStop && _longStopPromptOpen;

  /// Starts a trip for [group]. A trip already running is kept as it is.
  Future<void> start({
    required TourGroup group,
    required String tripId,
    required DateTime? plannedFinalEta,
    required JourneyServiceCopy copy,
  }) async {
    if (isTracking) return;
    final now = _now();
    _lifecycle.start(id: tripId, tourId: group.id, now: now);
    _group = group;
    _plannedFinalEta = plannedFinalEta;
    _copy = copy;
    _settings = store.readSettings();
    _arrivedNow = {};
    _everArrived = {};
    _resetStillness();
    await _persistTrip(now, force: true);
    _rebuild();
    await _syncAlarms(now);
    _startStream();
    _startIdleTimer();
    notifyListeners();
  }

  /// Resumes the trip stored before the app closed (roadmap LJ-3.5). Rebuilds
  /// the plan and the alarms from the device store. Returns false when there is
  /// no such trip, or when it has been idle too long and is ended now.
  Future<bool> restore({
    required TourGroup group,
    required JourneyServiceCopy copy,
  }) async {
    if (isTracking) return true;
    final stored = store.readTrip();
    if (stored == null || stored.tourId != group.id) return false;
    _lifecycle.restore(stored);
    final now = _now();
    if (_lifecycle.endIfIdle(now) != null) {
      await _finishTrip();
      return false;
    }
    _group = group;
    _copy = copy;
    _settings = store.readSettings();
    final arrivals = store.readArrivals();
    final kept = arrivals != null && arrivals.tripId == stored.id;
    _arrivedNow = kept ? {...arrivals.arrivedNow} : {};
    _everArrived = kept ? {...arrivals.everArrived} : {};
    _resetStillness();
    _rebuild();
    await _syncAlarms(now);
    _startStream();
    _startIdleTimer();
    notifyListeners();
    return true;
  }

  /// Ends the running trip (rule 1). Its alarms are cancelled.
  Future<void> stop() async {
    if (!isTracking) return;
    _lifecycle.end();
    await _finishTrip();
  }

  /// Turns sharing on or off for the running trip (rule 2).
  Future<void> setSharing({required bool on}) async {
    if (!_lifecycle.setSharing(on: on)) return;
    await _persistTrip(_now(), force: true);
    if (isTracking) _startStream();
    notifyListeners();
  }

  /// Saves new alarm settings and applies them to the running trip.
  Future<void> updateSettings(JourneyAlarmSettings next) async {
    _settings = next;
    await store.saveSettings(next);
    if (isTracking) {
      _rebuild();
      await _syncAlarms(_now());
    }
    notifyListeners();
  }

  /// Hides the long-stop question until the next long stop.
  void dismissLongStopPrompt() {
    if (!_longStopPromptOpen) return;
    _longStopPromptOpen = false;
    notifyListeners();
  }

  /// Feeds one reading to the trip. The location stream calls this; the tests
  /// call it directly.
  @visibleForTesting
  Future<void> onFix(JourneyFix fix) async {
    if (_disposed || !isTracking) return;
    try {
      await _handleFix(fix);
    } catch (error, stackTrace) {
      logWarning('Live journey reading failed', error, stackTrace);
    }
    notifyListeners();
  }

  Future<void> _handleFix(JourneyFix fix) async {
    final now = _now();
    final tracker = _tracker;
    if (tracker == null) {
      // No route with coordinates: the trip still runs, with no alerts.
      if (_lifecycle.recordReading(now)) await _persistTrip(now);
      return;
    }
    final update = tracker.update(fix);
    if (update.verdict == FixVerdict.accepted) {
      _lifecycle.recordReading(now);
    }
    _snapshot = update.snapshot;
    final snap = update.snapshot;
    if (update.verdict == FixVerdict.accepted && !_readings.isClosed) {
      _readings.add(fix);
    }
    _still.observe(speedMps: snap.speedMps, at: now);
    _updateLongStop(now);
    _maybeResample(now);

    final engine = _engine;
    if (engine != null) {
      final alerts = engine.evaluate(at: fix.point, pastEndM: snap.pastEndM);
      for (final alert in alerts) {
        await _raise(alert);
      }
      final arrivedNow = engine.arrivedNowIds;
      final leftNow = _arrivedNow.difference(arrivedNow);
      for (final stopId in leftNow) {
        await _recordEvent(stopId, JourneyEventType.depart);
      }
      final changed = !setEquals(arrivedNow, _arrivedNow) ||
          !setEquals(engine.everArrivedIds, _everArrived);
      _arrivedNow = arrivedNow;
      _everArrived = engine.everArrivedIds;
      if (changed) await _persistArrivals();
      await _syncAlarms(now);
    }
    await _persistTrip(now);
  }

  void _updateLongStop(DateTime now) {
    final longStop = _still.isLongStop(now);
    if (longStop && !_longStop) _longStopPromptOpen = true;
    if (!longStop) _longStopPromptOpen = false;
    _longStop = longStop;
  }

  /// Samples less while the device is still for a long stop, and more while it
  /// moves. Restarts the stream when the plan changes.
  void _maybeResample(DateTime now) {
    final wanted = SamplingPlan.forState(
      moving: _still.isMoving,
      longStop: _still.isLongStop(now),
    );
    if (wanted.interval == _sampling.interval &&
        wanted.distanceFilterM == _sampling.distanceFilterM) {
      return;
    }
    _sampling = wanted;
    _startStream();
  }

  /// Raises one alert, honouring the settings and the mutes. Arrivals are
  /// recorded for the group even when the notice is muted.
  Future<void> _raise(HubAlert alert) async {
    final target = _targetById(alert.targetId);
    final trip = this.trip;
    if (target == null || trip == null) return;
    final isDestination = target.kind == AlertTargetKind.finalDestination;

    if (alert.kind == HubAlertKind.arrive) {
      await _recordEvent(target.id, JourneyEventType.arrive);
    }
    if (_settings.mutedTargetIds.contains(target.id)) return;
    if (!_alertEnabled(alert.kind, isDestination)) return;

    final presentation = presentAlert(
      tripId: trip.id,
      alert: alert,
      targetKind: target.kind,
      placeName: target.name,
      kmText: alert.kind == HubAlertKind.approach
          ? formatNumber((alert.distanceM / 1000).round())
          : '',
    );
    final title = text(presentation.title);
    final body = text(presentation.body);
    await notices.show(
      id: presentation.id,
      title: title,
      body: body,
      channel: presentation.channel,
      rings: presentation.rings,
      payload: jsonEncode({
        'kind': presentation.rings ? 'journey_alarm' : 'journey',
        'tourId': trip.tourId,
        'title': title,
        'body': body,
      }),
    );
    if (presentation.rings) onRing(presentation);
  }

  bool _alertEnabled(HubAlertKind kind, bool isDestination) {
    final s = _settings;
    switch (kind) {
      case HubAlertKind.approach:
        return isDestination ? s.finalApproach : s.hubApproach;
      case HubAlertKind.arrive:
        return isDestination ? s.finalArrivalAlarm : s.hubArrive;
      case HubAlertKind.overshoot:
        return s.overshootAlarm;
    }
  }

  AlertTarget? _targetById(String id) {
    for (final t in _targets.stops) {
      if (t.id == id) return t;
    }
    final destination = _targets.destination;
    return destination != null && destination.id == id ? destination : null;
  }

  Future<void> _recordEvent(String stopId, JourneyEventType type) async {
    final trip = this.trip;
    if (trip == null || !trip.sharing) return;
    try {
      await events.record(tourId: trip.tourId, stopId: stopId, type: type);
    } catch (error, stackTrace) {
      logWarning('Journey event was not recorded', error, stackTrace);
    }
  }

  /// Builds the trip's targets and engine from the group and the settings. The
  /// arrival state is kept, so an arrival does not ring again.
  void _rebuild() {
    final group = _group;
    if (group == null) return;
    _targets = journeyTargetsFor(
      group,
      hubApproachM: _settings.hubApproachThresholdsM,
      destinationApproachM: _settings.finalApproachThresholdsM,
    );
    final route = _targets.route;
    _tracker = route == null ? null : JourneyTracker(route: route);
    final all = [
      ..._targets.stops,
      if (_targets.destination != null) _targets.destination!,
    ];
    _engine = all.isEmpty
        ? null
        : (HubAlertEngine(targets: all)
          ..restoreState(arrivedNow: _arrivedNow, everArrived: _everArrived));
  }

  /// Keeps the device's time-based alarms in step with the plan (rule 8). The
  /// time alarm uses the live ETA, or the planned arrival before the first
  /// reading. It is dropped once the destination has been reached.
  Future<void> _syncAlarms(DateTime now) async {
    final trip = this.trip;
    if (trip == null) return;
    final destination = _targets.destination;
    final reached =
        destination != null && _everArrived.contains(destination.id);
    DateTime? finalEta;
    if (!reached) {
      final toEnd = _snapshot?.etaToEnd;
      finalEta = toEnd != null ? now.add(toEnd) : _plannedFinalEta;
    }
    final plan = buildTripAlarmPlan(
      tripId: trip.id,
      stops: _targets.stops,
      finalDestination: destination,
      settings: _settings,
      now: now,
      finalEta: finalEta,
    );
    try {
      await scheduler.sync(plan: plan, textFor: _alarmText);
    } catch (error, stackTrace) {
      logWarning('Journey alarms could not be scheduled', error, stackTrace);
    }
  }

  /// The text of a time-based alarm. Only the ETA alarm has a fire time (the
  /// geofence alarms are raised by the tracker), so this is the ETA text.
  JourneyAlarmText _alarmText(TripAlarm alarm) {
    final place =
        _targetById(alarm.targetId)?.name ?? _targets.destination?.name ?? '';
    final minutes = formatNumber(_settings.etaFallbackLead.inMinutes);
    return JourneyAlarmText(
      title: text(JourneyText('alarm_title_eta', {'min': minutes})),
      body: text(JourneyText('alarm_body_place', {'place': place})),
    );
  }

  void _startStream() {
    _sub?.cancel();
    final copy = _copy;
    final serviceText = isSharing ? copy?.sharing : copy?.tracking;
    _sub = fixes(_sampling, copy?.title ?? '', serviceText ?? '').listen(
      (fix) => unawaited(onFix(fix)),
      onError: (Object error, StackTrace stackTrace) {
        logWarning('Journey location stream failed', error, stackTrace);
      },
    );
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(idleCheckEvery, (_) => unawaited(_checkIdle()));
  }

  Future<void> _checkIdle() async {
    if (!isTracking) return;
    if (_lifecycle.endIfIdle(_now()) != null) await _finishTrip();
  }

  void _resetStillness() {
    _still = StationaryDetector();
    _sampling = SamplingPlan.moving;
    _longStop = false;
    _longStopPromptOpen = false;
  }

  Future<void> _persistTrip(DateTime now, {bool force = false}) async {
    final last = _lastPersistAt;
    if (!force && last != null && now.difference(last) < persistEvery) return;
    _lastPersistAt = now;
    await store.saveTrip(trip);
  }

  Future<void> _persistArrivals() {
    final trip = this.trip;
    if (trip == null) return Future.value();
    return store.saveArrivals(JourneyArrivals(
      tripId: trip.id,
      arrivedNow: _arrivedNow,
      everArrived: _everArrived,
    ));
  }

  Future<void> _finishTrip() async {
    _sub?.cancel();
    _sub = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _tracker = null;
    _engine = null;
    _targets = JourneyTargets.none;
    _snapshot = null;
    _arrivedNow = {};
    _everArrived = {};
    _plannedFinalEta = null;
    _group = null;
    _copy = null;
    _resetStillness();
    try {
      await scheduler.cancelAll();
    } catch (error, stackTrace) {
      logWarning('Journey alarms could not be cancelled', error, stackTrace);
    }
    await store.saveTrip(null);
    await store.clearArrivals();
    _lastPersistAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _idleTimer?.cancel();
    unawaited(_readings.close());
    super.dispose();
  }
}
