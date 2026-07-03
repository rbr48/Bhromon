enum DecayStatus { fresh, aging, stale }

class FreshnessAge {
  final DateTime lastConfirmed;

  const FreshnessAge(this.lastConfirmed);

  int get daysSinceConfirmed => DateTime.now().difference(lastConfirmed).inDays;
  
  bool isStale() => daysSinceConfirmed > 180;
  
  double decayFactor() {
    final diff = DateTime.now().difference(lastConfirmed);
    final ageHours = diff.isNegative ? 0.0 : diff.inHours.toDouble();
    return 1.0 / (1.0 + ageHours / 24.0);
  }
  
  DecayStatus get status => switch (daysSinceConfirmed) {
    < 30  => DecayStatus.fresh,
    < 180 => DecayStatus.aging,
    _     => DecayStatus.stale,
  };
}
