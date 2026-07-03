import '../entities/location_pin.dart';
import '../value_objects/trust_tier.dart';

/// Computes a "Discovery Score" for a pin (0–100).
/// High score = hidden gem. Low score = well-known.
class DiscoveryScoreService {
  static double compute(LocationPin pin) {
    double score = 0;

    // 1. Remoteness: pins far from city centres get higher score
    // (We approximate remoteness by visitCount — real remoteness needs road data)
    final visits = pin.visitCount;
    if (visits == 0) {
      score += 40;
    } else if (visits < 5) {
      score += 30;
    } else if (visits < 20) {
      score += 20;
    } else if (visits < 50) {
      score += 10;
    }
    // 0 for 50+ visits

    // 2. Low trip log count
    final logs = pin.linkedTripIds.length;
    if (logs == 0) {
      score += 30;
    } else if (logs < 3) {
      score += 20;
    } else if (logs < 10) {
      score += 10;
    }

    // 3. Trust tier: unverified/community = possibly newer/undiscovered
    if (pin.trustTier == TrustTier.unverified) {
      score += 15;
    } else if (pin.trustTier == TrustTier.community) {
      score += 10;
    }

    // 4. No description yet = truly undiscovered
    if (pin.description == null || pin.description!.isEmpty) score += 10;

    // 5. No photos = undiscovered
    if (pin.photos.isEmpty && pin.imageUrl == null) score += 5;

    return score.clamp(0, 100);
  }

  static bool isHiddenGem(LocationPin pin) => compute(pin) >= 60;

  static String label(double score) {
    if (score >= 80) return '🔭 Undiscovered';
    if (score >= 60) return '💎 Hidden Gem';
    if (score >= 40) return '🌿 Off the Beaten Path';
    if (score >= 20) return '📍 Known Spot';
    return '🌟 Popular';
  }

  static String emoji(double score) {
    if (score >= 80) return '🔭';
    if (score >= 60) return '💎';
    if (score >= 40) return '🌿';
    if (score >= 20) return '📍';
    return '🌟';
  }
}
