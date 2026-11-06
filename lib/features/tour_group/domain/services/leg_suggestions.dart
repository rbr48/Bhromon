import 'journey_geometry.dart';

/// What the readings suggest about a leg (roadmap LJ-5.2).
enum LegSuggestionKind { depart, arrive }

/// A suggested change to the shared plan. It changes nothing until a person
/// confirms it (roadmap rule 11).
class LegSuggestion {
  const LegSuggestion({required this.kind, required this.legKey});

  final LegSuggestionKind kind;
  final String legKey;
}

/// Suggests that a leg has started or ended (roadmap LJ-5.2 and rule 11).
///
/// A leg that has not started is a candidate to depart once the group is more than
/// [leaveRadiusM] from where it starts. A leg that is underway is a candidate to
/// arrive once the group is within [arriveRadiusM] of where it ends. A suggestion is
/// raised only after the same candidate has held for [stableFor], so one stray
/// reading cannot raise it. A change of candidate starts the wait again. Each
/// suggestion is raised once for each leg and kind.
class LegSuggestionEngine {
  LegSuggestionEngine({
    this.stableFor = const Duration(minutes: 2),
    this.leaveRadiusM = 1000,
    this.arriveRadiusM = 1000,
  });

  final Duration stableFor;
  final double leaveRadiusM;
  final double arriveRadiusM;

  String? _candidate;
  DateTime? _since;
  final Set<String> _raised = {};

  /// Feeds one reading for [legKey]. [from] and [to] are the ends of the leg, or
  /// null when they have no place. [underway] says the leg has started. Returns a
  /// suggestion the first time it is due, and null otherwise.
  LegSuggestion? observe({
    required String legKey,
    required bool underway,
    required GeoPoint? from,
    required GeoPoint? to,
    required GeoPoint at,
    required DateTime now,
  }) {
    LegSuggestionKind? kind;
    if (!underway && from != null && distanceM(at, from) > leaveRadiusM) {
      kind = LegSuggestionKind.depart;
    } else if (underway && to != null && distanceM(at, to) <= arriveRadiusM) {
      kind = LegSuggestionKind.arrive;
    }
    if (kind == null) {
      _candidate = null;
      _since = null;
      return null;
    }
    final key = '${kind.name}|$legKey';
    if (_raised.contains(key)) return null;
    if (_candidate != key) {
      _candidate = key;
      _since = now;
      return null;
    }
    if (now.difference(_since!) < stableFor) return null;
    _raised.add(key);
    _candidate = null;
    _since = null;
    return LegSuggestion(kind: kind, legKey: legKey);
  }
}
