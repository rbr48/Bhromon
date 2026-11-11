// Pure domain models for Tour Group Engine

import 'expense_models.dart';
import 'itinerary_models.dart';
import 'date_codec.dart';
import 'samity_models.dart';
import '../services/emergency_numbers.dart';

/// Used by copyWith to tell "not passed" apart from an explicit null.
const Object _keep = Object();

enum TourRole {
  owner,
  admin,
  member;

  static TourRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'owner':
        return TourRole.owner;
      case 'admin':
        return TourRole.admin;
      default:
        return TourRole.member;
    }
  }

  String toValue() => name;
  bool get isAdminOrOwner => this == TourRole.owner || this == TourRole.admin;
}

enum TourMemberStatus {
  active,
  invited;

  static TourMemberStatus fromString(String? status) {
    switch (status?.toLowerCase()) {
      case 'invited':
        return TourMemberStatus.invited;
      default:
        return TourMemberStatus.active;
    }
  }

  String toValue() => name;
}

enum TourType {
  beach,
  hill,
  nature,
  heritage,
  city,
  custom;

  static TourType fromString(String? type) {
    switch (type?.toLowerCase()) {
      case 'hill':
      case 'mountain':
        return TourType.hill;
      case 'nature':
      case 'forest':
        return TourType.nature;
      case 'heritage':
      case 'historical':
        return TourType.heritage;
      case 'city':
      case 'urban':
        return TourType.city;
      case 'custom':
      case 'other':
        return TourType.custom;
      default:
        return TourType.beach;
    }
  }

  String toValue() => name;

  String get labelBn {
    switch (this) {
      case TourType.beach:
        return '🏖️ সমুদ্র সৈকত (Beach)';
      case TourType.hill:
        return '⛰️ পাহাড় ও ট্র্যাকিং (Hill & Trek)';
      case TourType.nature:
        return '🌲 বন ও প্রকৃতি (Forest & Nature)';
      case TourType.heritage:
        return '🏛️ প্রত্নতাত্ত্বিক ও ঐতিহ্য (Heritage)';
      case TourType.city:
        return '🏙️ শহর ও আধুনিক ভ্রমণ (City Tour)';
      case TourType.custom:
        return '🎒 সাধারণ / কাস্টম ভ্রমণ (Custom Tour)';
    }
  }
}

class TourDayInfo {
  final String id; // 'day1', 'day2', etc.
  final int dayNumber; // 1, 2, etc.
  final DateTime date;
  final String label; // e.g. 'ডে ১ (২৫ অক্টো)'

  const TourDayInfo({
    required this.id,
    required this.dayNumber,
    required this.date,
    required this.label,
  });
}

class TourMember {
  final String tourId;
  final String tourName;
  final String email;
  final String displayName;
  final String? photoUrl;
  final TourRole role;
  final TourMemberStatus status;
  final DateTime joinedAt;

  /// People this member's family counts as when expenses are shared (1-20).
  final int familyCount;

  /// Firebase Auth UID for direct WebRTC calling and notifications.
  final String? uid;

  const TourMember({
    required this.tourId,
    this.tourName = '',
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.familyCount = 1,
    this.uid,
  });

  bool get isOwner => role == TourRole.owner;

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'tourName': tourName,
      'email': normalizeEmail(email),
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.toValue(),
      'status': status.toValue(),
      'joinedAt': writeDate(joinedAt),
      'familyCount': familyCount.clamp(1, 20),
      if (uid != null && uid!.isNotEmpty) 'uid': uid,
    };
  }

  factory TourMember.fromMap(Map<String, dynamic> map) {
    return TourMember(
      tourId: map['tourId'] as String? ?? '',
      tourName: map['tourName'] as String? ?? '',
      email: normalizeEmail(map['email'] as String? ?? ''),
      displayName: map['displayName'] as String? ?? 'Explorer',
      photoUrl: map['photoUrl'] as String?,
      role: TourRole.fromString(map['role'] as String?),
      status: TourMemberStatus.fromString(map['status'] as String?),
      joinedAt: readDate(map['joinedAt']) ?? DateTime.now(),
      familyCount: ((map['familyCount'] as num?)?.toInt() ?? 1).clamp(1, 20),
      uid: map['uid'] as String?,
    );
  }
}

class TourModules {
  final bool seatsRooms;
  final bool tideSafety;
  final bool games;
  final bool chat;

  const TourModules({
    this.seatsRooms = true,
    this.tideSafety = true,
    this.games = true,
    this.chat = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'seatsRooms': seatsRooms,
      'tideSafety': tideSafety,
      'games': games,
      'chat': chat,
    };
  }

  factory TourModules.fromMap(Object? mapOrObj) {
    if (mapOrObj is! Map) return const TourModules();
    final map = mapOrObj;
    return TourModules(
      seatsRooms: map['seatsRooms'] as bool? ?? true,
      tideSafety: map['tideSafety'] as bool? ?? true,
      games: map['games'] as bool? ?? true,
      chat: map['chat'] as bool? ?? true,
    );
  }

  TourModules copyWith({
    bool? seatsRooms,
    bool? tideSafety,
    bool? games,
    bool? chat,
  }) {
    return TourModules(
      seatsRooms: seatsRooms ?? this.seatsRooms,
      tideSafety: tideSafety ?? this.tideSafety,
      games: games ?? this.games,
      chat: chat ?? this.chat,
    );
  }
}

/// Whether a group plans a trip, or is a private family circle that starts
/// without a trip (no dates, destination or travel modules to fill in).
enum GroupKind {
  tour,
  family;

  static GroupKind fromString(String? value) =>
      value == 'family' ? GroupKind.family : GroupKind.tour;
}

class TourGroup {
  final String id;
  final String name;
  final String description;
  final String destination;
  final String originCity;
  final TourType tourType;
  final String ownerEmail;
  final String ownerUid;
  final String inviteCode;
  final DateTime startDate;
  final DateTime endDate;
  final TourModules modules;
  final List<String> customSpots;
  final String? meetingPointTitle;
  final String? meetingPointNote;
  final String? meetingPointMapUrl;

  /// The group's photo: a media-server URL in the group's own space (folder
  /// `avatars`), or null for the default icon. Only an owner or admin changes it.
  final String? photoUrl;
  final DateTime createdAt;

  /// The places the tour visits, in order. Empty for tours made before
  /// itineraries; use [effectiveStops], which falls back to [destination].
  final List<TourStop> stops;

  /// How each leg is travelled, keyed "<fromId>><toId>" (see [routeLegKeys]).
  final Map<String, LegPlan> legPlans;

  /// Whether the route ends back at [originCity].
  final bool returnHome;

  /// The fund's budget and collection target.
  final FundBudget fundBudget;

  /// Whether this group plans a trip or is a family circle.
  final GroupKind kind;

  /// The workspace preset a circle was created with, such as [officePreset].
  /// Null for trips and for family circles made before presets.
  final String? preset;

  /// Whether Moments (posts and stories) is on. Only an office or campus can turn it
  /// off; a family circle, a mess or a trip always has it on.
  final bool momentsEnabled;

  /// Numbers every member can call or text in an emergency (at most ten).
  final List<EmergencyContact> emergencyContacts;

  /// The schedule of a rotating savings group (samity). Empty for every other circle.
  final SamityConfig samity;

  const TourGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.destination = 'Custom Destination',
    this.originCity = 'ঢাকা',
    this.tourType = TourType.beach,
    required this.ownerEmail,
    this.ownerUid = '',
    required this.inviteCode,
    required this.startDate,
    required this.endDate,
    this.modules = const TourModules(),
    this.customSpots = const [],
    this.meetingPointTitle,
    this.meetingPointNote,
    this.meetingPointMapUrl,
    this.photoUrl,
    required this.createdAt,
    this.stops = const [],
    this.legPlans = const {},
    this.returnHome = true,
    this.fundBudget = const FundBudget(),
    this.kind = GroupKind.tour,
    this.preset,
    this.momentsEnabled = true,
    this.emergencyContacts = const [],
    this.samity = const SamityConfig(),
  });

  /// A family circle rather than a trip.
  bool get isFamily => kind == GroupKind.family;

  /// The preset of an office or team. See [preset].
  static const String officePreset = 'office';

  /// The preset of a campus, class, batch or club. See [preset].
  static const String campusPreset = 'campus';

  /// The preset of a mess or shared home: a shared meal arrangement or a shared
  /// flat. See [preset].
  static const String messPreset = 'mess';

  /// The preset of a housing society or apartment building: a family-style circle
  /// where the committee posts notices and residents raise service requests.
  static const String societyPreset = 'society';

  /// The preset of a rotating savings group (samity). See [samity].
  static const String samityPreset = 'samity';

  /// The preset of a school, coaching centre or class: teachers and admins post the
  /// notices, and parents and students answer them.
  static const String schoolPreset = 'school';

  /// The preset of a sports team or gym: the coach and admins post the notices, and
  /// members answer them.
  static const String sportsPreset = 'sports';

  /// The preset of a study or book club: a family-style circle where any member can
  /// post, with shared books, a reading schedule and shared costs.
  static const String studyPreset = 'study';

  /// The preset of a neighbourhood committee: the committee posts the notices, and
  /// residents raise service requests, as in a housing society.
  static const String committeePreset = 'committee';

  /// The preset of a friends circle: hangouts, adda, dining splits, parties and games.
  static const String friendsPreset = 'friends';

  /// The preset a stored value names, or null when it names none.
  static String? presetFrom(Object? value) {
    if (value == officePreset) return officePreset;
    if (value == campusPreset) return campusPreset;
    if (value == messPreset) return messPreset;
    if (value == societyPreset) return societyPreset;
    if (value == samityPreset) return samityPreset;
    if (value == schoolPreset) return schoolPreset;
    if (value == sportsPreset) return sportsPreset;
    if (value == studyPreset) return studyPreset;
    if (value == committeePreset) return committeePreset;
    if (value == friendsPreset) return friendsPreset;
    return null;
  }

  /// The preset as the group keeps it from its document. A value this app does not
  /// know is kept as it is, and is not read as no preset: the rules treat any preset as a
  /// preset, so a group the app cannot name is not a household, and it has no SOS.
  static String? storedPresetFrom(Object? value) {
    final known = presetFrom(value);
    if (known != null) return known;
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  static bool _matchesAnyKeyword(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Resolves the preset either from the explicit [preset] attribute, or inferred
  /// from the group's [name] when [preset] is unset.
  String? get effectivePreset {
    if (!isFamily) return null;
    if (preset != null && preset!.trim().isNotEmpty) return preset;
    final lower = name.toLowerCase().trim();
    if (_matchesAnyKeyword(lower, const [
      'friend',
      'বন্ধু',
      'ফ্রেন্ড',
      'দোস্ত',
      'আড্ডা',
      'dost',
      'gang',
      'squad',
      'buddy',
      'buddies',
    ])) {
      return friendsPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'office',
      'অফিস',
      'team',
      'টিম',
      'work',
      'কোম্পানি',
      'company',
      'corp',
      'colleague',
      'সহকর্মী',
    ])) {
      return officePreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'campus',
      'ক্যাম্পাস',
      'varsity',
      'ভার্সিটি',
      'university',
      'বিশ্ববিদ্যালয়',
      'college',
      'কলেজ',
      'batch',
      'ব্যাচ',
      'class',
      'ক্লাস',
      'dept',
      'department',
    ])) {
      return campusPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'mess',
      'মেস',
      'hostel',
      'হোস্টেল',
      'flat',
      'ফ্ল্যাট',
      'roommate',
      'রুমমেট',
      'bachelor',
      'ব্যাচেলর',
    ])) {
      return messPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'society',
      'সোসাইটি',
      'building',
      'বিল্ডিং',
      'apartment',
      'অ্যাপার্টমেন্ট',
      'tower',
      'টাওয়ার',
      'housing',
      'হাউজিং',
    ])) {
      return societyPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'samity',
      'সমিতি',
      'savings',
      'সঞ্চয়',
      'dps',
      'kisti',
      'কিস্তি',
    ])) {
      return samityPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'school',
      'স্কুল',
      'coaching',
      'কোচিং',
      'madrasa',
      'মাদ্রাসা',
      'academy',
      'একাডেমি',
    ])) {
      return schoolPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'sports',
      'খেলা',
      'football',
      'ফুটবল',
      'cricket',
      'ক্রিকেট',
      'gym',
      'জিম',
      'fitness',
      'ফিটনেস',
      'club',
      'ক্লাব',
      'badminton',
      'ব্যাডমিন্টন',
    ])) {
      return sportsPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'study',
      'বই',
      'পাঠচক্র',
      'reading',
      'library',
      'লাইব্রেরি',
      'book club',
    ])) {
      return studyPreset;
    }
    if (_matchesAnyKeyword(lower, const [
      'committee',
      'কমিটি',
      'council',
      'পরিষদ',
      'association',
      'সমিতি পরিষদ',
    ])) {
      return committeePreset;
    }
    return null;
  }

  /// An office or team: a family-style circle where only admins write notices.
  bool get isOffice => preset == officePreset;

  /// A campus, class, batch or club: the office rules, with campus copy.
  bool get isCampus => preset == campusPreset;

  /// A mess or shared home: a family-style circle with its own categories and
  /// channels. The owner and admins post its notices, and members answer them.
  bool get isMess => preset == messPreset;

  /// A housing society or apartment building: a family-style circle with its own
  /// categories, channels and service requests.
  bool get isSociety => preset == societyPreset;

  /// A rotating savings group: a family-style circle with a schedule of payments and
  /// payouts.
  bool get isSamity => preset == samityPreset;

  /// A school, coaching centre or class: a family-style circle where the teachers post
  /// the notices. SOS stays on.
  bool get isSchool => preset == schoolPreset;

  /// A sports team or gym: a family-style circle where the coach posts the notices.
  bool get isSports => preset == sportsPreset;

  /// A study or book club: a family-style circle where any member can post.
  bool get isStudy => preset == studyPreset;

  /// A neighbourhood committee: a family-style circle with notices and service requests,
  /// as in a housing society.
  bool get isCommittee => preset == committeePreset;

  /// A friends circle: a casual family-style circle for friends with hangout plans,
  /// dining splits, shared checklists, games and photos. Any friend can post.
  bool get isFriends => preset == friendsPreset;

  /// An office or a campus: a workspace, where the household tiles and records do not
  /// apply and SOS is refused.
  bool get isManaged => isOffice || isCampus;

  /// Whether this group has the SOS feature: the alert, the SOS row, the Family Safety
  /// hub and the alert banners. Only a trip, a household (a plain family circle), a mess
  /// and a housing society have it. Every other group is off, and an unknown preset is
  /// off too.
  ///
  /// The rules (`sosAllowedTour` in firestore.rules) and the VPS (`sos_policy.py`) apply
  /// the same rule to the stored preset, so keep the three in step.
  bool get supportsSafetyAlerts =>
      preset == null || preset == messPreset || preset == societyPreset;

  /// A plain household: a family circle with no preset. Only a household keeps
  /// dependents, the family album and family dates.
  bool get isHousehold => isFamily && preset == null;

  /// Whether the owner and admins alone post notices: an office, a campus, a mess, a
  /// housing society or a samity. Members answer them. A plain family circle lets any
  /// member post.
  bool get hasManagedNotices =>
      isOffice ||
      isCampus ||
      isMess ||
      isSociety ||
      isSamity ||
      isSchool ||
      isSports ||
      isCommittee;

  /// Whether Moments is open to members: always, except when an office or campus has
  /// turned it off.
  bool get momentsOpen => !isManaged || momentsEnabled;

  /// The id the origin city has in leg keys.
  static const String originId = 'origin';

  /// The itinerary, or one stop at [destination] covering the whole tour for
  /// tours made before itineraries.
  List<TourStop> get effectiveStops => stops.isNotEmpty
      ? stops
      : [
          TourStop(
            id: 'main',
            name: destination,
            kind: tourType,
            arrive: startDate,
            leave: endDate,
          ),
        ];

  /// "Cox's Bazar → Saint Martin's → Bandarban".
  String get destinationSummary =>
      effectiveStops.map((s) => s.name).join(' → ');

  /// The stop the group is at on [day], or null between stops.
  TourStop? stopOn(DateTime day) {
    for (final s in effectiveStops) {
      if (s.covers(day)) return s;
    }
    return null;
  }

  /// The active stop on [day] (or first stop), stripped of any ' → ' arrows.
  String currentDestination([DateTime? day]) {
    final activeStop =
        (day != null ? stopOn(day) : null) ?? effectiveStops.firstOrNull;
    if (activeStop != null && activeStop.name.trim().isNotEmpty) {
      return activeStop.name.trim();
    }
    final raw = destination.trim();
    if (raw.contains(' → ')) {
      return raw.split(' → ').first.trim();
    }
    return raw.isNotEmpty ? raw : 'Destination';
  }

  /// The legs in order: origin to the first stop, stop to stop, and back to
  /// the origin when [returnHome] is set.
  List<String> get routeLegKeys {
    final ids = [originId, ...effectiveStops.map((s) => s.id)];
    if (returnHome) ids.add(originId);
    return [
      for (var i = 0; i + 1 < ids.length; i++) '${ids[i]}>${ids[i + 1]}',
    ];
  }

  /// Calendar days the tour covers, counting the start and end dates whatever
  /// time of day they were picked at.
  int get totalDays {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final diff = end.difference(start).inDays;
    return diff < 0 ? 1 : diff + 1;
  }

  int get totalNights => totalDays > 1 ? totalDays - 1 : 0;

  /// True while [now] falls on one of the tour's calendar days.
  bool isLiveAt(DateTime now) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = DateTime(endDate.year, endDate.month, endDate.day + 1);
    return !now.isBefore(start) && now.isBefore(endExclusive);
  }

  String get durationText {
    final daysBn = _toBanglaNumber(totalDays);
    if (totalNights == 0) return '$daysBn দিন (ডে-ট্যুর)';
    final nightsBn = _toBanglaNumber(totalNights);
    return '$daysBn দিন $nightsBn রাত';
  }

  /// The trip's days, for the feed's day filter and the day tags on posts. A family
  /// circle has no trip, so it has no days.
  List<TourDayInfo> get daysList {
    if (isFamily) return const [];
    final list = <TourDayInfo>[];
    for (int i = 0; i < totalDays; i++) {
      final dayDate = startDate.add(Duration(days: i));
      final monthName = _banglaMonth(dayDate.month);
      final dayNumBn = _toBanglaNumber(dayDate.day);
      final dayIndexBn = _toBanglaNumber(i + 1);
      list.add(
        TourDayInfo(
          id: 'day${i + 1}',
          dayNumber: i + 1,
          date: dayDate,
          label: 'ডে $dayIndexBn ($dayNumBn $monthName)',
        ),
      );
    }
    return list;
  }

  static String _toBanglaNumber(int n) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    String s = n.toString();
    for (int i = 0; i < 10; i++) {
      s = s.replaceAll(en[i], bn[i]);
    }
    return s;
  }

  static String _banglaMonth(int m) {
    const months = [
      'জানু',
      'ফেব্রু',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টে',
      'অক্টো',
      'নভে',
      'ডিসে'
    ];
    if (m >= 1 && m <= 12) return months[m - 1];
    return '';
  }

  List<String> get recommendedSpots => recommendedSpotsFor(destination);

  /// Well-known spots for a destination name, or generic ones.
  static List<String> recommendedSpotsFor(String name) {
    final dest = name.toLowerCase();
    if (dest.contains('cox') || dest.contains('কক্সবাজার')) {
      return const [
        'লাবণী বিচ (Laboni Point)',
        'সুগন্ধা বিচ (Sugandha Point)',
        'কলাতলী বিচ ও পয়েন্ট (Kolatoli)',
        'ইনানী বিচ ও প্রবাল দ্বীপ (Inani Beach)',
        'পাটুয়ারটেক বিচ (Patuartek)',
        'হিমছড়ি পাহাড় ও ঝর্ণা (Himchari)',
        'মেরিন ড্রাইভ রোড (Marine Drive)',
        'বার্মিজ মার্কেট (Burmese Market)',
        'ডলফিন মোড় (Dolphin Point)',
        'অন্যান্য স্থান (Others)',
      ];
    } else if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return const [
        'রুইলুই পাড়া (Ruilui Para)',
        'কংলাক পাহাড় চূড়া (Konglak Peak)',
        'সাজেক হ্যালিপ্যাড (Sajek Helipad)',
        'স্টোন গার্ডেন (Stone Garden)',
        'লুসাই ভিলেজ (Lushai Village)',
        'রিছাং ঝর্ণা (Richang Waterfall)',
        'আলুটিলা গুহা ও সুরঙ্গ (Alutila Cave)',
        'অন্যান্য স্থান (Others)',
      ];
    } else if (dest.contains('sylhet') ||
        dest.contains('সিলেট') ||
        dest.contains('sreemangal') ||
        dest.contains('শ্রীমঙ্গল')) {
      return const [
        'রাতারগুল সোয়াম্প ফরেস্ট (Ratargul)',
        'বিছনাকান্দি (Bisnakandi)',
        'জাফলং জিরো পয়েন্ট (Jaflong)',
        'ভোলাগঞ্জ সাদা পাথর (Sada Pathor)',
        'লালাখাল পান্না নদী (Lalakhal)',
        'মালনীছড়া চা বাগান (Malnicherra Tea)',
        'মাধবপুর লেক (Madhabpur Lake)',
        'লাউয়াছড়া জাতীয় উদ্যান (Lawachara)',
        'অন্যান্য স্থান (Others)',
      ];
    } else if (dest.contains('bandarban') || dest.contains('বান্দরবান')) {
      return const [
        'নীলগিরি রিসোর্ট ও মেঘলোক (Nilgiri)',
        'নীলাচল ভিউপয়েন্ট (Nilachal)',
        'স্বর্ণমন্দির / বুদ্ধ ধাতু জাদি (Golden Temple)',
        'বগা লেক (Boga Lake)',
        'নাফাখুম জলপ্রপাত (Nafakhum)',
        'মেঘলা পর্যটন কমপ্লেক্স (Meghla)',
        'চিম্বুক পাহাড় (Chimbuk Hill)',
        'অন্যান্য স্থান (Others)',
      ];
    } else if (dest.contains('kuakata') || dest.contains('কুয়াকাটা')) {
      return const [
        'কুয়াকাটা সৈকত সূর্যোদয় ও সূর্যাস্ত পয়েন্ট',
        'ঝাউবন ও লাল কাঁকড়ার চর',
        'ফাতরার বন ম্যানগ্রোভ অঞ্চল',
        'লেম্বুর চর ও তিন নদীর মোহনা',
        'মিশ্রীপাড়া বৌদ্ধ মন্দির ও সীমা বিহার',
        'অন্যান্য স্থান (Others)',
      ];
    } else if (dest.contains('sundarban') || dest.contains('সুন্দরবন')) {
      return const [
        'করমজল বন্যপ্রাণী কেন্দ্র',
        'কটকা বিচ ও ওয়াচ টাওয়ার',
        'হাড়বাড়িয়া ইকোট্যুরিজম কেন্দ্র',
        'হিরণ পয়েন্ট ও নীলকমল',
        'দুবলার চর ও আলোরকোল',
        'অন্যান্য স্থান (Others)',
      ];
    } else {
      return const [
        'প্রধান হোটেল / রিসোর্ট (Hotel/Resort)',
        'যাত্রা পয়েন্ট / স্টেশন (Departure/Station)',
        'দর্শনীয় স্পট ১ (Attraction 1)',
        'দর্শনীয় স্পট ২ (Attraction 2)',
        'দর্শনীয় স্পট ৩ (Attraction 3)',
        'বিখ্যাত রেস্তোরাঁ ও ক্যাফে (Food & Dine)',
        'স্থানীয় বাজার ও কেনাকাটা (Local Market)',
        'অন্যান্য স্থান (Others)',
      ];
    }
  }

  List<String> get allSpots {
    final list = <String>[];
    for (final s in customSpots) {
      if (s.trim().isNotEmpty && !list.contains(s.trim())) {
        list.add(s.trim());
      }
    }
    // Spots for every stop on the itinerary, not just the first destination.
    final names = stops.isEmpty ? [destination] : stops.map((s) => s.name);
    for (final name in names) {
      for (final s in recommendedSpotsFor(name)) {
        if (!list.contains(s)) list.add(s);
      }
    }
    return list;
  }

  TourGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? destination,
    String? originCity,
    TourType? tourType,
    String? ownerEmail,
    String? ownerUid,
    String? inviteCode,
    DateTime? startDate,
    DateTime? endDate,
    TourModules? modules,
    List<String>? customSpots,
    Object? meetingPointTitle = _keep,
    Object? meetingPointNote = _keep,
    Object? meetingPointMapUrl = _keep,
    Object? photoUrl = _keep,
    DateTime? createdAt,
    List<TourStop>? stops,
    Map<String, LegPlan>? legPlans,
    bool? returnHome,
    FundBudget? fundBudget,
    GroupKind? kind,
    String? preset,
    bool? momentsEnabled,
    List<EmergencyContact>? emergencyContacts,
    SamityConfig? samity,
  }) {
    return TourGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      destination: destination ?? this.destination,
      originCity: originCity ?? this.originCity,
      tourType: tourType ?? this.tourType,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerUid: ownerUid ?? this.ownerUid,
      inviteCode: inviteCode ?? this.inviteCode,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      modules: modules ?? this.modules,
      customSpots: customSpots ?? this.customSpots,
      // Meeting point fields may be cleared, so an explicit null must win.
      meetingPointTitle: identical(meetingPointTitle, _keep)
          ? this.meetingPointTitle
          : meetingPointTitle as String?,
      meetingPointNote: identical(meetingPointNote, _keep)
          ? this.meetingPointNote
          : meetingPointNote as String?,
      meetingPointMapUrl: identical(meetingPointMapUrl, _keep)
          ? this.meetingPointMapUrl
          : meetingPointMapUrl as String?,
      photoUrl:
          identical(photoUrl, _keep) ? this.photoUrl : photoUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      stops: stops ?? this.stops,
      legPlans: legPlans ?? this.legPlans,
      returnHome: returnHome ?? this.returnHome,
      fundBudget: fundBudget ?? this.fundBudget,
      kind: kind ?? this.kind,
      preset: preset ?? this.preset,
      momentsEnabled: momentsEnabled ?? this.momentsEnabled,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      samity: samity ?? this.samity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'destination': destination,
      'originCity': originCity,
      'tourType': tourType.toValue(),
      'ownerEmail': normalizeEmail(ownerEmail),
      'ownerUid': ownerUid,
      'inviteCode': inviteCode,
      'startDate': writeDate(startDate),
      'endDate': writeDate(endDate),
      'modules': modules.toMap(),
      'customSpots': customSpots,
      'createdAt': writeDate(createdAt),
      'stops': [for (final st in stops) st.toMap()],
      'legPlans': {for (final e in legPlans.entries) e.key: e.value.toMap()},
      'returnHome': returnHome,
      'kind': kind.name,
      if (preset != null) 'preset': preset,
      if (!momentsEnabled) 'momentsEnabled': false,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'emergencyContacts': [for (final c in emergencyContacts) c.toMap()],
      if (samity.hasSettings) 'samity': samity.toMap(),
      if (!fundBudget.isEmpty) 'fundBudget': fundBudget.toMap(),
      'schemaVersion': 4,
    };
  }

  factory TourGroup.fromMap(String id, Map<dynamic, dynamic> map) {
    final createdAt = readDate(map['createdAt']) ?? DateTime.now();
    final startDate = readDate(map['startDate']) ?? createdAt;
    final endDate = readDate(map['endDate']) ?? startDate;
    // Older notice-board writes stored the meeting point as a nested map.
    final legacyMeeting =
        map['meetingPoint'] is Map ? (map['meetingPoint'] as Map) : null;
    return TourGroup(
      id: id,
      name: map['name']?.toString() ?? 'Family Tour',
      description: map['description']?.toString() ?? '',
      destination: map['destination']?.toString() ?? 'Custom Destination',
      originCity: map['originCity']?.toString() ?? 'ঢাকা',
      tourType: TourType.fromString(map['tourType']?.toString()),
      ownerEmail: normalizeEmail(map['ownerEmail']?.toString() ?? ''),
      ownerUid: map['ownerUid']?.toString() ?? '',
      inviteCode: map['inviteCode']?.toString() ?? '',
      startDate: startDate,
      endDate: endDate,
      modules: TourModules.fromMap(map['modules']),
      customSpots: (map['customSpots'] is Iterable)
          ? (map['customSpots'] as Iterable).map((e) => e.toString()).toList()
          : const [],
      meetingPointTitle: map['meetingPointTitle']?.toString() ??
          legacyMeeting?['title']?.toString(),
      meetingPointNote: map['meetingPointNote']?.toString() ??
          legacyMeeting?['note']?.toString(),
      meetingPointMapUrl: map['meetingPointMapUrl']?.toString() ??
          legacyMeeting?['mapUrl']?.toString(),
      createdAt: createdAt,
      stops: readStops(map['stops']),
      legPlans: readLegPlans(map['legPlans']),
      returnHome: map['returnHome'] as bool? ?? true,
      kind: GroupKind.fromString(map['kind']?.toString()),
      preset: storedPresetFrom(map['preset']),
      momentsEnabled: map['momentsEnabled'] != false,
      photoUrl:
          map['photoUrl'] is String && (map['photoUrl'] as String).isNotEmpty
              ? map['photoUrl'] as String
              : null,
      emergencyContacts: parseEmergencyContacts(map['emergencyContacts']),
      fundBudget: FundBudget.fromMap(map['fundBudget']),
      samity: SamityConfig.fromMap(map['samity']),
    );
  }
}

/// Lightweight preview of a group for direct invite landing screens.
class TourGroupPreview {
  final String tourId;
  final String name;
  final String? photoUrl;
  final String? preset;
  final TourType? tourType;
  final String? destination;
  final bool isAlreadyMember;

  const TourGroupPreview({
    required this.tourId,
    required this.name,
    this.photoUrl,
    this.preset,
    this.tourType,
    this.destination,
    this.isAlreadyMember = false,
  });
}
