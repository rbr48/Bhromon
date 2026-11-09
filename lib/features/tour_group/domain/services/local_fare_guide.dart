/// Comprehensive Local Transport Fare Guide and Calculator for Bangladesh Tourism.
///
/// Provides transit route fare estimates for popular Bangladeshi travel
/// hubs including Sajek Valley, Tanguar Haor, Sreemangal, Jaflong, Bandarban,
/// Cox's Bazar, Sundarbans, and Kuakata.
///
/// Fares include authoritative sourcing (BRTA, Local Jeep/Boat Samities)
/// and quarterly audit dates per ROADMAP.md (Task 9.2).
library;

/// Represents a specific local transit route in Bangladesh.
class LocalTransitRoute {
  const LocalTransitRoute({
    required this.id,
    required this.destination,
    required this.destinationBn,
    required this.division,
    required this.divisionBn,
    required this.origin,
    required this.originBn,
    required this.routeDescription,
    required this.vehicleType,
    required this.vehicleTitle,
    required this.minFare,
    required this.maxFare,
    required this.capacity,
    required this.fareType,
    required this.fareTypeBn,
    required this.tips,
    this.source = 'বিআরটিএ ও স্থানীয় যানবাহন সমিতি',
    this.asOf = '2026-11',
  });

  final String id;
  final String destination;
  final String destinationBn;
  final String division;
  final String divisionBn;
  final String origin;
  final String originBn;
  final String routeDescription;

  /// Vehicle category: 'chander_gari', 'boat', 'cng', 'microbus', 'motorcycle', 'ship', 'mahendra'.
  final String vehicleType;
  final String vehicleTitle;

  /// Minimum fare in Bangladeshi Taka (BDT).
  final int minFare;

  /// Maximum estimated fare in Bangladeshi Taka (BDT).
  final int maxFare;

  /// Nominal passenger capacity for one vehicle.
  final int capacity;

  /// Fare calculation basis:
  /// - 'per_vehicle_round_trip': Vehicle reservation for round trip (e.g. Sajek 1 night)
  /// - 'per_vehicle_day': Vehicle reservation for entire day tour
  /// - 'per_vehicle_one_way': One-way trip per vehicle
  /// - 'per_person_round_trip': Ticket cost per person
  /// - 'per_person_package': Full board per person (e.g. Houseboat / Sundarbans)
  /// - 'per_boat_day': Boat reservation per day
  final String fareType;
  final String fareTypeBn;

  /// Local tips, advisories, escort rules, or seasonal variations.
  final List<String> tips;

  /// Verified authority or sourcing samity for this fare.
  final String source;

  /// Audit date when this fare was verified (e.g. '2026-11').
  final String asOf;

  bool get isPerPerson =>
      fareType == 'per_person_round_trip' || fareType == 'per_person_package';
}

/// Calculation output for passenger fare estimations.
class FareCalculationResult {
  const FareCalculationResult({
    required this.route,
    required this.passengerCount,
    required this.vehiclesNeeded,
    required this.totalMinFare,
    required this.totalMaxFare,
    required this.perPersonMinFare,
    required this.perPersonMaxFare,
  });

  final LocalTransitRoute route;
  final int passengerCount;
  final int vehiclesNeeded;
  final int totalMinFare;
  final int totalMaxFare;
  final int perPersonMinFare;
  final int perPersonMaxFare;

  String formatSummary() {
    final buffer = StringBuffer()
      ..writeln('🇧🇩 ${route.destinationBn} লোকাল ভাড়া হিসাব')
      ..writeln('রুট: ${route.routeDescription}')
      ..writeln('বাহন: ${route.vehicleTitle}')
      ..writeln('যাত্রী সংখ্যা: $passengerCount জন')
      ..writeln('প্রয়োজনীয় বাহন: $vehiclesNeeded টি');

    if (route.isPerPerson) {
      buffer.writeln('ভিত্তি: ${route.fareTypeBn}');
    }

    buffer
      ..writeln('মোট আনুমানিক ভাড়া: ৳$totalMinFare – ৳$totalMaxFare')
      ..writeln('মাথাপিছু খরচ: ৳$perPersonMinFare – ৳$perPersonMaxFare');

    if (route.tips.isNotEmpty) {
      buffer.writeln('\nটিপস ও সতর্কতা:');
      for (final tip in route.tips) {
        buffer.writeln('• $tip');
      }
    }
    return buffer.toString();
  }
}

/// Repository and computation engine for Bangladesh local transit fares.
class LocalFareGuide {
  const LocalFareGuide();

  static const List<LocalTransitRoute> catalog = [
    // ── SAJEK VALLEY & KHAGRACHHARI ──────────────────────────────────────────
    LocalTransitRoute(
      id: 'sajek_chander_gari_rt',
      source: 'খাগড়াছড়ি জিপ মালিক সমিতি ও বিআরটিএ',
      asOf: '2026-11',
      destination: 'Sajek Valley',
      destinationBn: 'সাজেক ভ্যালি',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Khagrachhari',
      originBn: 'খাগড়াছড়ি',
      routeDescription: 'খাগড়াছড়ি জিপ সমিতি ⇄ সাজেক ভ্যালি (দীঘিনালা হয়ে)',
      vehicleType: 'chander_gari',
      vehicleTitle: 'চাঁদের গাড়ি (৪-হুইল ড্রাইভ জিপ)',
      minFare: 8500,
      maxFare: 11000,
      capacity: 13,
      fareType: 'per_vehicle_round_trip',
      fareTypeBn: 'প্রতি গাড়ি (রাউন্ড ট্রিপ + ১ রাত অবস্থান)',
      tips: [
        'সেনাবাহিনী এসকর্ট সময়: সকাল ১০:৩০ এবং বিকাল ৩:০০ (দীঘিনালা থেকে)।',
        'চাঁদের গাড়ি সমিতির অফিশিয়াল বুথ থেকে নির্ধারিত টোকেন সংগ্রহ করুন।',
        'ড্রাইভার ও হেল্পারের খাবার খরচ সাধারণত পর্যটকদের বহন করতে হয়।',
      ],
    ),
    LocalTransitRoute(
      id: 'sajek_mahindra_rt',
      destination: 'Sajek Valley',
      destinationBn: 'সাজেক ভ্যালি',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Khagrachhari',
      originBn: 'খাগড়াছড়ি',
      routeDescription: 'খাগড়াছড়ি ⇄ সাজেক ভ্যালি (মহিন্দ্র অটো)',
      vehicleType: 'mahendra',
      vehicleTitle: 'মহিন্দ্র / পিকআপ',
      minFare: 5500,
      maxFare: 7500,
      capacity: 8,
      fareType: 'per_vehicle_round_trip',
      fareTypeBn: 'প্রতি বাহন (রাউন্ড ট্রিপ + ১ রাত)',
      tips: [
        'ছোট দলের জন্য সাশ্রয়ী, তবে পাহাড়ি খাড়া রাস্তায় জিপ অধিক নিরাপদ।',
      ],
    ),
    LocalTransitRoute(
      id: 'khagrachhari_local_cng',
      destination: 'Khagrachhari Spots',
      destinationBn: 'খাগড়াছড়ি লোকাল স্পট',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Khagrachhari Town',
      originBn: 'খাগড়াছড়ি শহর',
      routeDescription: 'আলুটিলা গুহা + তারেং + রিছাং ঝরনা (রিজার্ভ ডে ট্যুর)',
      vehicleType: 'cng',
      vehicleTitle: 'সিএনজি অটোরিকশা',
      minFare: 1200,
      maxFare: 1800,
      capacity: 4,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি অটোরিকশা (সারাদিন রিজার্ভ)',
      tips: [
        'আলুটিলা গুহায় প্রবেশের জন্য মশাল প্রতি ৩০-৪০ টাকা।',
      ],
    ),

    // ── TANGUAR HAOR & SUNAMGANJ ─────────────────────────────────────────────
    LocalTransitRoute(
      id: 'tanguar_trawler_day',
      destination: 'Tanguar Haor',
      destinationBn: 'টাঙ্গুয়ার হাওড়',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Sunamganj / Tahirpur',
      originBn: 'তাহিরপুর / সুনামগঞ্জ',
      routeDescription:
          'তাহিরপুর ⇄ ওয়াচ টাওয়ার, নিলাদ্রি লেক, শিমুল বাগান, বারিক্কা টিলা',
      vehicleType: 'boat',
      vehicleTitle: 'ইঞ্জিন চালিত ট্রলার / বড় নৌকা',
      minFare: 4000,
      maxFare: 7000,
      capacity: 18,
      fareType: 'per_boat_day',
      fareTypeBn: 'প্রতি ট্রলার (সারাদিন রিজার্ভ)',
      tips: [
        'বর্ষা ও শরৎকালে (জুলাই–অক্টোবর) হাওড়ের সৌন্দর্য উপভোগের সেরা সময়।',
        'মাঝির সাথে যাওয়ার পূর্বে সব স্পটে থামার চুক্তি নিশ্চিত করে নিন।',
        'লাইফ জ্যাকেট ব্যবহার নিশ্চিত করুন।',
      ],
    ),
    LocalTransitRoute(
      id: 'tanguar_houseboat_pkg',
      destination: 'Tanguar Haor',
      destinationBn: 'টাঙ্গুয়ার হাওড়',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Sunamganj Saheb Bari Ghat',
      originBn: 'সুনামগঞ্জ সাহেব বাড়ি ঘাট',
      routeDescription:
          'প্রিমিয়াম হাউসবোট ভ্রমণ (১ রাত ২ দিন + সব বেলার খাবার)',
      vehicleType: 'boat',
      vehicleTitle: 'প্রিমিয়াম কাঠের হাউসবোট',
      minFare: 28000,
      maxFare: 55000,
      capacity: 14,
      fareType: 'per_vehicle_round_trip',
      fareTypeBn: 'সম্পূর্ণ বোট রিজার্ভ (১ রাত ২ দিন প্যাকেজ)',
      tips: [
        'এসি/নন-এসি কেবিন, সংযুক্ত ওয়াশরুম এবং দেশি খাবারের ব্যবস্থা থাকে।',
        'ছুটির দিনগুলোতে কমপক্ষে ৩-৪ সপ্তাহ পূর্বে বুকিং দিতে হয়।',
      ],
    ),
    LocalTransitRoute(
      id: 'tahirpur_niladri_bike',
      destination: 'Tanguar Haor',
      destinationBn: 'টাঙ্গুয়ার হাওড়',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Tahirpur',
      originBn: 'তাহিরপুর ঘাট',
      routeDescription: 'তাহিরপুর ⇄ টেকেরঘাট নিলাদ্রি শহীদ সিরাজ লেক',
      vehicleType: 'motorcycle',
      vehicleTitle: 'লোকাল মোটরসাইকেল / বাইক',
      minFare: 250,
      maxFare: 400,
      capacity: 1,
      fareType: 'per_person_round_trip',
      fareTypeBn: 'প্রতি ব্যক্তি (যাতায়াত)',
      tips: [
        'শুকনো মৌসুমে বাইকে সহজেই সব স্পটে যাওয়া যায়।',
      ],
    ),

    // ── SREEMANGAL & SYLHET ──────────────────────────────────────────────────
    LocalTransitRoute(
      id: 'sreemangal_cng_tour',
      destination: 'Sreemangal',
      destinationBn: 'শ্রীমঙ্গল',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Sreemangal Town',
      originBn: 'শ্রীমঙ্গল শহর',
      routeDescription:
          'লাউয়াছড়া জাতীয় উদ্যান + মাধবপুর লেক + নূরজাহান চা বাগান',
      vehicleType: 'cng',
      vehicleTitle: 'সিএনজি অটোরিকশা (রিজার্ভ)',
      minFare: 1400,
      maxFare: 2000,
      capacity: 4,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি অটোরিকশা (সারাদিন রিজার্ভ)',
      tips: [
        'সকাল সকাল বের হলে লাউয়াছড়ার বন্যপ্রাণী ও পাখি সহজে চোখে পড়ে।',
        'মাধবপুর লেকে পদ্মফুল দেখতে হলে দুপুরের আগে যাওয়া ভালো।',
      ],
    ),
    LocalTransitRoute(
      id: 'sylhet_jaflong_micro',
      destination: 'Jaflong',
      destinationBn: 'জাফলং ও লালাখাল',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Sylhet City',
      originBn: 'সিলেট শহর',
      routeDescription: 'সিলেট শহর ⇄ জাফলং জিরো পয়েন্ট ও মায়াবী ঝরনা',
      vehicleType: 'microbus',
      vehicleTitle: 'নোয়া / হাইয়েস মাইক্রোবাস',
      minFare: 4500,
      maxFare: 6200,
      capacity: 10,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি মাইক্রোবাস (সারাদিন রিজার্ভ)',
      tips: [
        'জাফলং জিরো পয়েন্টে ট্রলার ভাড়া প্রতি নৌকা ৮০০-১,২০০ টাকা।',
      ],
    ),
    LocalTransitRoute(
      id: 'sylhet_ratargul_dinghy',
      destination: 'Ratargul',
      destinationBn: 'রাতারগুল সোয়াম্প ফরেস্ট',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: 'Motorghat / Chowrangee Ghat',
      originBn: 'মোটরঘাট / চৌরঙ্গী ঘাট',
      routeDescription:
          'রাতারগুল সংরক্ষিত বনের ভেতর ডিঙ্গি নৌকা ভ্রমণ (১.৫ ঘণ্টা)',
      vehicleType: 'boat',
      vehicleTitle: 'ডিঙ্গি কাঠের নৌকা',
      minFare: 850,
      maxFare: 1200,
      capacity: 5,
      fareType: 'per_boat_day',
      fareTypeBn: 'প্রতি ডিঙ্গি নৌকা (বন বিভাগ নির্ধারিত রেট)',
      tips: [
        'বন বিভাগের নির্ধারিত টিকিট কাউন্টার থেকে রশিদ নিয়ে নৌকায় উঠুন।',
      ],
    ),
    LocalTransitRoute(
      id: 'sylhet_bholaganj_boat',
      destination: 'Bholaganj Shadapathor',
      destinationBn: 'ভোলাগঞ্জ সাদাপাথর',
      division: 'Sylhet',
      divisionBn: 'সিলেট',
      origin: '10 No. Ferry Ghat',
      originBn: '১০ নম্বর ঘাট',
      routeDescription: '১০ নম্বর ঘাট ⇄ সাদাপাথর পয়েন্ট (যাতায়াত ও অপেক্ষা)',
      vehicleType: 'boat',
      vehicleTitle: 'ইঞ্জিন চালিত ট্রলার',
      minFare: 800,
      maxFare: 1100,
      capacity: 10,
      fareType: 'per_boat_day',
      fareTypeBn: 'প্রতি নৌকা (যাতায়াত ও ২ ঘণ্টা অবস্থান)',
      tips: [
        'নৌকা সমিতি নির্ধারিত টোকেন সংগ্রহ করুন। পাথর পয়েন্টে পানির স্রোত বেশি থাকে।',
      ],
    ),

    // ── BANDARBAN & HILL TRACTS ──────────────────────────────────────────────
    LocalTransitRoute(
      id: 'bandarban_nilgiri_chander',
      destination: 'Bandarban',
      destinationBn: 'বান্দরবান',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Bandarban Town',
      originBn: 'বান্দরবান শহর',
      routeDescription: 'বান্দরবান ⇄ নীলগিরি, চিম্বুক পাহাড়, শৈলপ্রপাত ঝরনা',
      vehicleType: 'chander_gari',
      vehicleTitle: 'চাঁদের গাড়ি (ল্যান্ড ক্রুজার / জিপ)',
      minFare: 6000,
      maxFare: 8000,
      capacity: 13,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি গাড়ি (সারাদিন রিজার্ভ)',
      tips: [
        'নীলগিরি রিসোর্টের প্রবেশ টিকিট আলাদা (প্রতি ব্যক্তি ১০০ টাকা + গাড়ি পার্কিং)।',
        'জাতীয় পরিচয়পত্র বা ফটোকপি সাথে রাখা বাধ্যতামূলক।',
      ],
    ),
    LocalTransitRoute(
      id: 'bandarban_thanchi_boat',
      destination: 'Thanchi & Remakri',
      destinationBn: 'থানচি ও রেমাক্রি',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Thanchi Ghat',
      originBn: 'থানচি ঘাট',
      routeDescription: 'থানচি ঘাট ⇄ সাঙ্গু নদী ক্রুজ ⇄ রেমাক্রি ফলস',
      vehicleType: 'boat',
      vehicleTitle: 'সাঙ্গু ইঞ্জিন বোট / ট্রলার',
      minFare: 4200,
      maxFare: 6000,
      capacity: 5,
      fareType: 'per_boat_day',
      fareTypeBn: 'প্রতি নৌকা (রাউন্ড ট্রিপ)',
      tips: [
        'বিজিবি ক্যাম্পে সবার নাম ও জাতীয় পরিচয়পত্র এন্ট্রি করতে হবে।',
        'রেমাক্রি থেকে নাফাখুম ট্র্যাকিংয়ে নিবন্ধিত গাইড নেওয়া বাধ্যতামূলক (৳১,৫০০–২,০০০)।',
      ],
    ),

    // ── COX\'S BAZAR & SAINT MARTIN ─────────────────────────────────────────
    LocalTransitRoute(
      id: 'coxsbazar_marine_drive_jeep',
      destination: 'Cox\'s Bazar',
      destinationBn: 'কক্সবাজার',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Kolatoli / Laboni',
      originBn: 'কলাতলী পয়েন্ট',
      routeDescription: 'মেরিন ড্রাইভ রোড ⇄ হিমছড়ি পাহাড় ⇄ ইনানী পাথুরে সৈকত',
      vehicleType: 'chander_gari',
      vehicleTitle: 'খোলা জিপ / চাঁদের গাড়ি',
      minFare: 2800,
      maxFare: 4200,
      capacity: 12,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি জিপ (বিকেল ও সূর্যাস্ত সফর)',
      tips: [
        'বিকেল ৩টায় যাত্রা শুরু করলে ইনানীতে চমৎকার সূর্যাস্ত উপভোগ করা যায়।',
      ],
    ),
    LocalTransitRoute(
      id: 'saint_martin_ship_ticket',
      destination: 'Saint Martin\'s Island',
      destinationBn: 'সেন্ট মার্টিন দ্বীপ',
      division: 'Chattogram',
      divisionBn: 'চট্টগ্রাম',
      origin: 'Teknaf / Inani Jetty',
      originBn: 'টেকনাফ / ইনানী জেটি',
      routeDescription: 'জেটি ⇄ সেন্ট মার্টিন মূল দ্বীপ (রিটার্ন শিপ টিকিট)',
      vehicleType: 'ship',
      vehicleTitle: 'সমুদ্রগামী ট্যুরিস্ট শিপ (কেয়ারী / বে ক্রুজ)',
      minFare: 950,
      maxFare: 2500,
      capacity: 1,
      fareType: 'per_person_round_trip',
      fareTypeBn: 'প্রতি ব্যক্তি (ওপেন ডেক / এসি কেবিন রিটার্ন)',
      tips: [
        'সেন্ট মার্টিনে প্লাস্টিক ব্যবহার সম্পূর্ণ নিষিদ্ধ।',
        'পরিবেশ অধিদপ্তর নির্দেশিকা ও জাহাজ চলাচলের অনুমতি সময়সূচি জেনে বুক করুন।',
      ],
    ),

    // ── KHULNA & SUNDARBANS ──────────────────────────────────────────────────
    LocalTransitRoute(
      id: 'sundarbans_karamjal_trawler',
      destination: 'Sundarbans',
      destinationBn: 'সুন্দরবন (করমজল)',
      division: 'Khulna',
      divisionBn: 'খুলনা',
      origin: 'Mongla Ghat',
      originBn: 'মোংলা ফেরিঘাট',
      routeDescription:
          'মোংলা ঘাট ⇄ পশুর নদী ⇄ করমজল কুমির প্রজনন কেন্দ্র ও ওয়াচ টাওয়ার',
      vehicleType: 'boat',
      vehicleTitle: 'ইঞ্জিন চালিত ট্যুরিস্ট ট্রলার',
      minFare: 2600,
      maxFare: 4000,
      capacity: 15,
      fareType: 'per_boat_day',
      fareTypeBn: 'প্রতি ট্রলার (যাতায়াত ও ৩ ঘণ্টা অপেক্ষা)',
      tips: [
        'বন বিভাগের প্রবেশ ফি ও গাইড ফি কাউন্টারে নির্ধারিত মূল্যে পরিশোধ করুন।',
        'হরিণ ও কুমিরকে খাবার দেওয়া সম্পূর্ণ নিষেধ।',
      ],
    ),
    LocalTransitRoute(
      id: 'khulna_mongla_mahendra',
      destination: 'Sundarbans / Mongla',
      destinationBn: 'মোংলা ঘাট',
      division: 'Khulna',
      divisionBn: 'খুলনা',
      origin: 'Khulna Rupsha Bridge',
      originBn: 'খুলনা রূপসা ব্রিজ',
      routeDescription: 'রূপসা মোড় ⇄ মোংলা ফেরিঘাট সরাসরি',
      vehicleType: 'mahendra',
      vehicleTitle: 'মহিন্দ্র ডিজেল থ্রি-হুইলার',
      minFare: 1200,
      maxFare: 1700,
      capacity: 6,
      fareType: 'per_vehicle_one_way',
      fareTypeBn: 'প্রতি মহিন্দ্র (রিজার্ভ একমুখী)',
      tips: [
        'শেয়ারে গেলে জনপ্রতি ১০০-১৩০ টাকা। বড় দলের জন্য রিজার্ভ সুবিধাজনক।',
      ],
    ),

    // ── KUAKATA ──────────────────────────────────────────────────────────────
    LocalTransitRoute(
      id: 'kuakata_beach_bike_tour',
      destination: 'Kuakata',
      destinationBn: 'কুয়াকাটা সৈকত',
      division: 'Barishal',
      divisionBn: 'বরিশাল',
      origin: 'Kuakata Zero Point',
      originBn: 'জিরো পয়েন্ট',
      routeDescription:
          'গঙ্গামতি সৈকত + লাল কাঁকড়া চর + ফাতরার বন + রাখাইন পল্লী',
      vehicleType: 'motorcycle',
      vehicleTitle: 'ট্যুরিস্ট মোটরসাইকেল (ড্রাইভারসহ)',
      minFare: 600,
      maxFare: 900,
      capacity: 2,
      fareType: 'per_vehicle_day',
      fareTypeBn: 'প্রতি বাইক (৪টি প্রধান স্পট ভিজিট)',
      tips: [
        'সূর্যোদয়ের সময় লাল কাঁকড়ার বিচ সবচেয়ে প্রাণবন্ত থাকে (সকাল ৫:৩০–৭:০০)।',
      ],
    ),
  ];

  /// Calculates total fare range and per-person cost breakdown.
  FareCalculationResult calculate({
    required LocalTransitRoute route,
    required int passengerCount,
  }) {
    final validPassengers = passengerCount <= 0 ? 1 : passengerCount;

    if (route.isPerPerson) {
      final totalMin = route.minFare * validPassengers;
      final totalMax = route.maxFare * validPassengers;
      return FareCalculationResult(
        route: route,
        passengerCount: validPassengers,
        vehiclesNeeded: validPassengers,
        totalMinFare: totalMin,
        totalMaxFare: totalMax,
        perPersonMinFare: route.minFare,
        perPersonMaxFare: route.maxFare,
      );
    }

    final vehiclesNeeded = (validPassengers / route.capacity).ceil();
    final count = vehiclesNeeded <= 0 ? 1 : vehiclesNeeded;
    final totalMin = route.minFare * count;
    final totalMax = route.maxFare * count;
    final perPersonMin = (totalMin / validPassengers).ceil();
    final perPersonMax = (totalMax / validPassengers).ceil();

    return FareCalculationResult(
      route: route,
      passengerCount: validPassengers,
      vehiclesNeeded: count,
      totalMinFare: totalMin,
      totalMaxFare: totalMax,
      perPersonMinFare: perPersonMin,
      perPersonMaxFare: perPersonMax,
    );
  }

  /// Filters routes by search query and optional division.
  List<LocalTransitRoute> search({
    String query = '',
    String division = 'All',
  }) {
    final q = query.trim().toLowerCase();
    return catalog.where((r) {
      if (division != 'All' && r.division != division) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.destination.toLowerCase().contains(q) ||
          r.destinationBn.contains(q) ||
          r.origin.toLowerCase().contains(q) ||
          r.originBn.contains(q) ||
          r.routeDescription.toLowerCase().contains(q) ||
          r.routeDescription.contains(q) ||
          r.vehicleTitle.toLowerCase().contains(q) ||
          r.vehicleTitle.contains(q);
    }).toList();
  }
}
