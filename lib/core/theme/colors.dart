import 'package:flutter/material.dart';
import '../value_objects/trust_tier.dart';

class AppColors {
  // Forest Green Palette
  static const Color darkGreen = Color(0xFF1B4332);
  static const Color midGreen = Color(0xFF2D6A4F);
  static const Color leafGreen = Color(0xFF40916C);
  static const Color mintGreen = Color(0xFF74C69D);
  static const Color paleGreen = Color(0xFFD8F3DC);

  // Accents
  static const Color gold = Color(0xFFF4A261);
  static const Color amber = Color(0xFFE76F51);
  static const Color lightGold = Color(0xFFFFD166);

  // Trust Tiers
  static const Color tierUnverified = Color(0xFFADB5BD);
  static const Color tierCommunity = Color(0xFF74C69D); // Mint green
  static const Color tierVerifiedExplorer = Color(0xFFF4A261); // Gold
  static const Color tierRegionExpert = Color(0xFF1B4332); // Deep green
  static const Color tierPioneer = Color(0xFFE76F51); // Amber
  static const Color tierLocalKnowledge = Color(0xFF8B5E3C); // Earthy brown

  // Neutrals
  static const Color offWhite = Color(0xFFF8FAFB);
  static const Color darkText = Color(0xFF1A1A2E);
  static const Color grayText = Color(0xFF5C6B73);
  
  static const Color backgroundLight = Color(0xFFF8FAFB);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1E1E1E);

  static Color forTier(TrustTier tier) {
    switch (tier) {
      case TrustTier.unverified:
        return tierUnverified;
      case TrustTier.community:
        return tierCommunity;
      case TrustTier.verified:
        return tierVerifiedExplorer;
      case TrustTier.regionExpert:
        return tierRegionExpert;
      case TrustTier.pioneer:
        return tierPioneer;
    }
  }
}
