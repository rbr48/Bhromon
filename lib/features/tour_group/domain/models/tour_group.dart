// Pure domain models for Tour Group Engine

import 'expense_models.dart';
import 'itinerary_models.dart';
import 'date_codec.dart';

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

  factory TourModules.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TourModules();
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
    required this.createdAt,
    this.stops = const [],
    this.legPlans = const {},
    this.returnHome = true,
    this.fundBudget = const FundBudget(),
  });

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

  List<TourDayInfo> get daysList {
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
    DateTime? createdAt,
    List<TourStop>? stops,
    Map<String, LegPlan>? legPlans,
    bool? returnHome,
    FundBudget? fundBudget,
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
      createdAt: createdAt ?? this.createdAt,
      stops: stops ?? this.stops,
      legPlans: legPlans ?? this.legPlans,
      returnHome: returnHome ?? this.returnHome,
      fundBudget: fundBudget ?? this.fundBudget,
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
      if (!fundBudget.isEmpty) 'fundBudget': fundBudget.toMap(),
      'schemaVersion': 4,
    };
  }

  factory TourGroup.fromMap(String id, Map<String, dynamic> map) {
    final createdAt = readDate(map['createdAt']) ?? DateTime.now();
    final startDate = readDate(map['startDate']) ?? createdAt;
    final endDate = readDate(map['endDate']) ?? startDate;
    // Older notice-board writes stored the meeting point as a nested map.
    final legacyMeeting = map['meetingPoint'] as Map<String, dynamic>?;
    return TourGroup(
      id: id,
      name: map['name'] as String? ?? 'Family Tour',
      description: map['description'] as String? ?? '',
      destination: map['destination'] as String? ?? 'Custom Destination',
      originCity: map['originCity'] as String? ?? 'ঢাকা',
      tourType: TourType.fromString(map['tourType'] as String?),
      ownerEmail: normalizeEmail(map['ownerEmail'] as String? ?? ''),
      ownerUid: map['ownerUid'] as String? ?? '',
      inviteCode: map['inviteCode'] as String? ?? '',
      startDate: startDate,
      endDate: endDate,
      modules: TourModules.fromMap(map['modules'] as Map<String, dynamic>?),
      customSpots: (map['customSpots'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      meetingPointTitle: map['meetingPointTitle'] as String? ??
          legacyMeeting?['title'] as String?,
      meetingPointNote: map['meetingPointNote'] as String? ??
          legacyMeeting?['note'] as String?,
      meetingPointMapUrl: map['meetingPointMapUrl'] as String? ??
          legacyMeeting?['mapUrl'] as String?,
      createdAt: createdAt,
      stops: readStops(map['stops']),
      legPlans: readLegPlans(map['legPlans']),
      returnHome: map['returnHome'] as bool? ?? true,
      fundBudget: FundBudget.fromMap(map['fundBudget']),
    );
  }
}
