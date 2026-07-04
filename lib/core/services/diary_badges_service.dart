import '../entities/explorer_profile.dart';

/// 🏅 Service that auto-awards district-based diary badges.
/// Called after every diary entry publish via Cloud Function + client-side check.
class DiaryBadgesService {
  /// All badge definitions keyed by badge ID.
  static const Map<String, BadgeDef> badgeDefs = {
    'coastal_chronicler': BadgeDef(
      id: 'coastal_chronicler',
      emoji: '🌊',
      titleBn: 'উপকূলীয় কথক',
      titleEn: 'Coastal Chronicler',
      descBn: "কক্সবাজার, কুয়াকাটা ও সেন্টমার্টিন ডায়েরি করেছেন",
      requiredDistricts: ['কক্সবাজার', 'পটুয়াখালী', 'বরগুনা'],
    ),
    'hill_wanderer': BadgeDef(
      id: 'hill_wanderer',
      emoji: '⛰️',
      titleBn: 'পাহাড় পথিক',
      titleEn: 'Hill Wanderer',
      descBn: 'বান্দরবান, রাঙামাটি ও খাগড়াছড়ি ডায়েরি করেছেন',
      requiredDistricts: ['বান্দরবান', 'রাঙামাটি', 'খাগড়াছড়ি'],
    ),
    'forest_keeper': BadgeDef(
      id: 'forest_keeper',
      emoji: '🌿',
      titleBn: 'বনের রক্ষক',
      titleEn: 'Forest Keeper',
      descBn: 'সুন্দরবন, রাতারগুল ও লাউয়াছড়া অন্বেষণ করেছেন',
      requiredDistricts: ['বাগেরহাট', 'সিলেট', 'মৌলভীবাজার'],
    ),
    'heritage_seeker': BadgeDef(
      id: 'heritage_seeker',
      emoji: '🏛️',
      titleBn: 'ঐতিহ্য সন্ধানী',
      titleEn: 'Heritage Seeker',
      descBn: 'পাহাড়পুর, মহাস্থানগড় ও লালবাগ দুর্গ ডায়েরি করেছেন',
      requiredDistricts: ['নওগাঁ', 'বগুড়া', 'ঢাকা'],
    ),
    'tea_garden_explorer': BadgeDef(
      id: 'tea_garden_explorer',
      emoji: '🍵',
      titleBn: 'চা বাগান পর্যটক',
      titleEn: 'Tea Garden Explorer',
      descBn: 'সিলেট ও মৌলভীবাজারের চা বাগান ডায়েরি করেছেন',
      requiredDistricts: ['সিলেট', 'মৌলভীবাজার', 'হবিগঞ্জ'],
    ),
    'sundarbans_guardian': BadgeDef(
      id: 'sundarbans_guardian',
      emoji: '🐯',
      titleBn: 'সুন্দরবনের বন্ধু',
      titleEn: 'Sundarbans Guardian',
      descBn: 'সুন্দরবন এলাকার সব জেলায় ডায়েরি করেছেন',
      requiredDistricts: ['বাগেরহাট', 'সাতক্ষীরা', 'খুলনা'],
    ),
    'northern_nomad': BadgeDef(
      id: 'northern_nomad',
      emoji: '🌾',
      titleBn: 'উত্তরের যাযাবর',
      titleEn: 'Northern Nomad',
      descBn: 'রংপুর বিভাগের সব জেলা অন্বেষণ করেছেন',
      requiredDistricts: ['দিনাজপুর', 'রংপুর', 'পঞ্চগড়', 'ঠাকুরগাঁও'],
    ),
    'sylhet_wanderer': BadgeDef(
      id: 'sylhet_wanderer',
      emoji: '🌫️',
      titleBn: 'সিলেটের পথিক',
      titleEn: 'Sylhet Wanderer',
      descBn: 'সিলেট বিভাগের সব চার জেলায় ডায়েরি করেছেন',
      requiredDistricts: ['সিলেট', 'মৌলভীবাজার', 'হবিগঞ্জ', 'সুনামগঞ্জ'],
    ),
    'capital_explorer': BadgeDef(
      id: 'capital_explorer',
      emoji: '🏙️',
      titleBn: 'রাজধানী অন্বেষক',
      titleEn: 'Capital Explorer',
      descBn: 'ঢাকা বিভাগের ১০+ জেলায় ডায়েরি করেছেন',
      requiredDistricts: [
        'ঢাকা',
        'গাজীপুর',
        'নারায়ণগঞ্জ',
        'মুন্সীগঞ্জ',
        'নরসিংদী',
        'মানিকগঞ্জ',
        'টাঙ্গাইল',
        'কিশোরগঞ্জ',
        'ফরিদপুর',
        'রাজবাড়ী',
      ],
    ),
    'bangladesh_champion': BadgeDef(
      id: 'bangladesh_champion',
      emoji: '🏆',
      titleBn: 'বাংলাদেশ চ্যাম্পিয়ন',
      titleEn: 'Bangladesh Champion',
      descBn: '৩২+ জেলায় ভ্রমণ ডায়েরি করেছেন',
      // Any 32 districts — checked differently
      requiredDistricts: [],
      minDistrictCount: 32,
    ),
  };

  /// Returns the list of NEW badge IDs earned (not already in profile.badges).
  static List<String> checkAndAwardBadges(ExplorerProfile profile) {
    final visitedSet = profile.districtsDiaryLogged.toSet();
    final existing = profile.badges.toSet();
    final newBadges = <String>[];

    for (final entry in badgeDefs.entries) {
      if (existing.contains(entry.key)) continue; // already awarded

      final def = entry.value;
      bool earned;

      if (def.minDistrictCount != null && def.requiredDistricts.isEmpty) {
        // Count-based badge
        earned = visitedSet.length >= def.minDistrictCount!;
      } else {
        // All required districts must be visited
        earned = def.requiredDistricts.every((d) => visitedSet.contains(d));
      }

      if (earned) newBadges.add(entry.key);
    }

    return newBadges;
  }

  /// Returns badge definition for a given ID, null if unknown.
  static BadgeDef? getBadge(String id) => badgeDefs[id];
}

class BadgeDef {
  final String id;
  final String emoji;
  final String titleBn;
  final String titleEn;
  final String descBn;
  final List<String> requiredDistricts;
  final int? minDistrictCount;

  const BadgeDef({
    required this.id,
    required this.emoji,
    required this.titleBn,
    required this.titleEn,
    required this.descBn,
    required this.requiredDistricts,
    this.minDistrictCount,
  });
}
