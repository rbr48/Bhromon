import 'package:hive/hive.dart';

import '../domain/services/journey_trip.dart';
import '../domain/services/trip_alarm_plan.dart';

/// Where the journey data lives on the device: a key-value store. The app uses
/// a Hive box, and the tests use memory.
abstract class JourneyPrefsBackend {
  Object? read(String key);
  Future<void> write(String key, Object value);
  Future<void> delete(String key);
}

/// The Hive box `journey_prefs` (roadmap section 4, Storage).
class HiveJourneyPrefsBackend implements JourneyPrefsBackend {
  HiveJourneyPrefsBackend(this._box);

  static const String boxName = 'journey_prefs';

  /// Opens the box. Hive must be initialised first.
  static Future<HiveJourneyPrefsBackend> open() async {
    return HiveJourneyPrefsBackend(await Hive.openBox<dynamic>(boxName));
  }

  final Box<dynamic> _box;

  @override
  Object? read(String key) => _box.get(key);

  @override
  Future<void> write(String key, Object value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);
}

/// Memory only, for tests and for a device where the box cannot be opened.
class MemoryJourneyPrefsBackend implements JourneyPrefsBackend {
  final Map<String, Object> _values = {};

  @override
  Object? read(String key) => _values[key];

  @override
  Future<void> write(String key, Object value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Which targets had been reached on a trip, so a restart does not ring them
/// again (see `HubAlertEngine.restoreState`).
class JourneyArrivals {
  const JourneyArrivals({
    required this.tripId,
    required this.arrivedNow,
    required this.everArrived,
  });

  final String tripId;
  final Set<String> arrivedNow;
  final Set<String> everArrived;
}

/// The journey settings and the active trip, kept on the device (roadmap
/// LJ-2.3 and LJ-3.6). Nothing here holds a position.
class JourneyPrefsStore {
  JourneyPrefsStore(this._backend);

  static const String _tripKey = 'active_trip';
  static const String _settingsKey = 'alarm_settings';
  static const String _arrivalsKey = 'arrivals';
  static const String _disclosureKey = 'background_disclosure_seen';

  final JourneyPrefsBackend _backend;

  /// The trip that was running when the app last closed, if any.
  JourneyTrip? readTrip() {
    final raw = _backend.read(_tripKey);
    if (raw is! Map) return null;
    return JourneyTrip.fromMap(raw.cast<Object?, Object?>());
  }

  Future<void> saveTrip(JourneyTrip? trip) {
    if (trip == null) return _backend.delete(_tripKey);
    return _backend.write(_tripKey, trip.toMap());
  }

  JourneyAlarmSettings readSettings() {
    final raw = _backend.read(_settingsKey);
    if (raw is! Map) return const JourneyAlarmSettings();
    return settingsFromMap(raw.cast<Object?, Object?>());
  }

  Future<void> saveSettings(JourneyAlarmSettings settings) {
    return _backend.write(_settingsKey, settingsToMap(settings));
  }

  JourneyArrivals? readArrivals() {
    final raw = _backend.read(_arrivalsKey);
    if (raw is! Map) return null;
    final tripId = raw['tripId'];
    if (tripId is! String) return null;
    return JourneyArrivals(
      tripId: tripId,
      arrivedNow: _strings(raw['arrivedNow']),
      everArrived: _strings(raw['everArrived']),
    );
  }

  Future<void> saveArrivals(JourneyArrivals arrivals) {
    return _backend.write(_arrivalsKey, {
      'tripId': arrivals.tripId,
      'arrivedNow': arrivals.arrivedNow.toList(),
      'everArrived': arrivals.everArrived.toList(),
    });
  }

  Future<void> clearArrivals() => _backend.delete(_arrivalsKey);

  /// Whether the person has read the background-location disclosure (roadmap
  /// LJ-2.2). It is shown again only if they have not.
  bool readDisclosureSeen() => _backend.read(_disclosureKey) == true;

  Future<void> saveDisclosureSeen() => _backend.write(_disclosureKey, true);
}

Set<String> _strings(Object? raw) {
  if (raw is! List) return <String>{};
  return {
    for (final item in raw)
      if (item is String) item,
  };
}

/// The settings as plain values, for the device store. Thresholds are metres;
/// the ETA lead is whole minutes.
Map<String, Object> settingsToMap(JourneyAlarmSettings s) => {
      'hubApproach': s.hubApproach,
      'hubApproachThresholdsM': s.hubApproachThresholdsM,
      'hubArrive': s.hubArrive,
      'finalApproach': s.finalApproach,
      'finalApproachThresholdsM': s.finalApproachThresholdsM,
      'finalArrivalAlarm': s.finalArrivalAlarm,
      'overshootAlarm': s.overshootAlarm,
      'etaFallback': s.etaFallback,
      'etaFallbackLeadMin': s.etaFallbackLead.inMinutes,
      'mutedTargetIds': s.mutedTargetIds.toList(),
    };

/// Reads [settingsToMap]'s output. A missing or wrong field keeps its default,
/// so an old or damaged record still loads.
JourneyAlarmSettings settingsFromMap(Map<Object?, Object?> map) {
  const d = JourneyAlarmSettings();
  bool flag(String key, bool fallback) {
    final v = map[key];
    return v is bool ? v : fallback;
  }

  List<double> thresholds(String key, List<double> fallback) {
    final v = map[key];
    if (v is! List) return fallback;
    final values = [
      for (final item in v)
        if (item is num && item > 0) item.toDouble(),
    ];
    return values.isEmpty ? fallback : values;
  }

  final lead = map['etaFallbackLeadMin'];
  return JourneyAlarmSettings(
    hubApproach: flag('hubApproach', d.hubApproach),
    hubApproachThresholdsM:
        thresholds('hubApproachThresholdsM', d.hubApproachThresholdsM),
    hubArrive: flag('hubArrive', d.hubArrive),
    finalApproach: flag('finalApproach', d.finalApproach),
    finalApproachThresholdsM:
        thresholds('finalApproachThresholdsM', d.finalApproachThresholdsM),
    finalArrivalAlarm: flag('finalArrivalAlarm', d.finalArrivalAlarm),
    overshootAlarm: flag('overshootAlarm', d.overshootAlarm),
    etaFallback: flag('etaFallback', d.etaFallback),
    etaFallbackLead: lead is num && lead >= 5 && lead <= 180
        ? Duration(minutes: lead.toInt())
        : d.etaFallbackLead,
    mutedTargetIds: _strings(map['mutedTargetIds']),
  );
}
