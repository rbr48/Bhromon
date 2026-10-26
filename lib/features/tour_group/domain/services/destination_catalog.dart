import '../models/tour_group.dart';

/// A well-known place a tour can visit or start from. Coordinates are
/// approximate centre points, good for distance estimates and map links, not
/// for turn-by-turn navigation.
class DestinationPreset {
  const DestinationPreset({
    required this.id,
    required this.nameEn,
    required this.nameBn,
    required this.lat,
    required this.lng,
    required this.kind,
    required this.region,
    this.aliases = const [],
    this.isCity = false,
  });

  final String id;
  final String nameEn;
  final String nameBn;
  final double lat;
  final double lng;
  final TourType kind;

  /// The division, for grouping in the picker.
  final String region;

  /// Other spellings people type, lower case.
  final List<String> aliases;

  /// A city a tour usually starts from.
  final bool isCity;

  /// The name in the reader's language.
  String nameFor(String languageCode) => languageCode == 'bn' ? nameBn : nameEn;

  bool matches(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (t.contains(nameEn.toLowerCase()) || t.contains(nameBn)) return true;
    return aliases.any(t.contains);
  }
}

/// Bangladesh's main tourist destinations and the cities tours start from.
const List<DestinationPreset> kDestinationCatalog = [
  // ── Cities tours start from ───────────────────────────────────────────
  DestinationPreset(
      id: 'dhaka',
      nameEn: 'Dhaka',
      nameBn: 'ঢাকা',
      lat: 23.8103,
      lng: 90.4125,
      kind: TourType.city,
      region: 'Dhaka',
      isCity: true),
  DestinationPreset(
      id: 'chattogram',
      nameEn: 'Chattogram',
      nameBn: 'চট্টগ্রাম',
      lat: 22.3569,
      lng: 91.7832,
      kind: TourType.city,
      region: 'Chattogram',
      isCity: true,
      aliases: ['chittagong', 'ctg']),
  DestinationPreset(
      id: 'sylhet',
      nameEn: 'Sylhet',
      nameBn: 'সিলেট',
      lat: 24.8949,
      lng: 91.8687,
      kind: TourType.nature,
      region: 'Sylhet',
      isCity: true),
  DestinationPreset(
      id: 'rajshahi',
      nameEn: 'Rajshahi',
      nameBn: 'রাজশাহী',
      lat: 24.3745,
      lng: 88.6042,
      kind: TourType.city,
      region: 'Rajshahi',
      isCity: true),
  DestinationPreset(
      id: 'khulna',
      nameEn: 'Khulna',
      nameBn: 'খুলনা',
      lat: 22.8456,
      lng: 89.5403,
      kind: TourType.city,
      region: 'Khulna',
      isCity: true),
  DestinationPreset(
      id: 'barishal',
      nameEn: 'Barishal',
      nameBn: 'বরিশাল',
      lat: 22.7010,
      lng: 90.3535,
      kind: TourType.city,
      region: 'Barishal',
      isCity: true,
      aliases: ['barisal']),
  DestinationPreset(
      id: 'rangpur',
      nameEn: 'Rangpur',
      nameBn: 'রংপুর',
      lat: 25.7439,
      lng: 89.2752,
      kind: TourType.city,
      region: 'Rangpur',
      isCity: true),
  DestinationPreset(
      id: 'mymensingh',
      nameEn: 'Mymensingh',
      nameBn: 'ময়মনসিংহ',
      lat: 24.7471,
      lng: 90.4203,
      kind: TourType.city,
      region: 'Mymensingh',
      isCity: true),
  DestinationPreset(
      id: 'cumilla',
      nameEn: 'Cumilla',
      nameBn: 'কুমিল্লা',
      lat: 23.4607,
      lng: 91.1809,
      kind: TourType.heritage,
      region: 'Chattogram',
      isCity: true,
      aliases: ['comilla']),
  DestinationPreset(
      id: 'bogura',
      nameEn: 'Bogura',
      nameBn: 'বগুড়া',
      lat: 24.8465,
      lng: 89.3773,
      kind: TourType.city,
      region: 'Rajshahi',
      isCity: true,
      aliases: ['bogra']),

  // ── Sea and beaches ───────────────────────────────────────────────────
  DestinationPreset(
      id: 'coxs_bazar',
      nameEn: "Cox's Bazar",
      nameBn: 'কক্সবাজার',
      lat: 21.4272,
      lng: 92.0058,
      kind: TourType.beach,
      region: 'Chattogram',
      aliases: ['cox', 'coxs']),
  DestinationPreset(
      id: 'inani',
      nameEn: 'Inani Beach',
      nameBn: 'ইনানী সৈকত',
      lat: 21.2290,
      lng: 92.0480,
      kind: TourType.beach,
      region: 'Chattogram',
      aliases: ['inani']),
  DestinationPreset(
      id: 'teknaf',
      nameEn: 'Teknaf',
      nameBn: 'টেকনাফ',
      lat: 20.8645,
      lng: 92.2986,
      kind: TourType.beach,
      region: 'Chattogram'),
  DestinationPreset(
      id: 'saint_martin',
      nameEn: "Saint Martin's Island",
      nameBn: 'সেন্টমার্টিন দ্বীপ',
      lat: 20.6237,
      lng: 92.3234,
      kind: TourType.beach,
      region: 'Chattogram',
      aliases: ['saint martin', 'st martin', 'st. martin', 'সেন্ট মার্টিন']),
  DestinationPreset(
      id: 'kuakata',
      nameEn: 'Kuakata',
      nameBn: 'কুয়াকাটা',
      lat: 21.8167,
      lng: 90.1167,
      kind: TourType.beach,
      region: 'Barishal'),
  DestinationPreset(
      id: 'nijhum_dwip',
      nameEn: 'Nijhum Dwip',
      nameBn: 'নিঝুম দ্বীপ',
      lat: 22.0500,
      lng: 91.0300,
      kind: TourType.beach,
      region: 'Chattogram',
      aliases: ['nijhum']),
  DestinationPreset(
      id: 'patenga',
      nameEn: 'Patenga Beach',
      nameBn: 'পতেঙ্গা সৈকত',
      lat: 22.2367,
      lng: 91.7911,
      kind: TourType.beach,
      region: 'Chattogram',
      aliases: ['patenga']),

  // ── Hills ──────────────────────────────────────────────────────────────
  DestinationPreset(
      id: 'bandarban',
      nameEn: 'Bandarban',
      nameBn: 'বান্দরবান',
      lat: 22.1953,
      lng: 92.2184,
      kind: TourType.hill,
      region: 'Chattogram'),
  DestinationPreset(
      id: 'nilgiri',
      nameEn: 'Nilgiri',
      nameBn: 'নীলগিরি',
      lat: 21.9136,
      lng: 92.3375,
      kind: TourType.hill,
      region: 'Chattogram'),
  DestinationPreset(
      id: 'thanchi',
      nameEn: 'Thanchi & Nafakhum',
      nameBn: 'থানচি ও নাফাখুম',
      lat: 21.7550,
      lng: 92.4830,
      kind: TourType.hill,
      region: 'Chattogram',
      aliases: ['thanchi', 'nafakhum', 'remakri']),
  DestinationPreset(
      id: 'rangamati',
      nameEn: 'Rangamati',
      nameBn: 'রাঙামাটি',
      lat: 22.6533,
      lng: 92.1789,
      kind: TourType.hill,
      region: 'Chattogram'),
  DestinationPreset(
      id: 'kaptai',
      nameEn: 'Kaptai Lake',
      nameBn: 'কাপ্তাই লেক',
      lat: 22.5000,
      lng: 92.2167,
      kind: TourType.nature,
      region: 'Chattogram',
      aliases: ['kaptai']),
  DestinationPreset(
      id: 'khagrachhari',
      nameEn: 'Khagrachhari',
      nameBn: 'খাগড়াছড়ি',
      lat: 23.1193,
      lng: 91.9847,
      kind: TourType.hill,
      region: 'Chattogram',
      aliases: ['khagrachari']),
  DestinationPreset(
      id: 'sajek',
      nameEn: 'Sajek Valley',
      nameBn: 'সাজেক ভ্যালি',
      lat: 23.3820,
      lng: 92.2938,
      kind: TourType.hill,
      region: 'Chattogram',
      aliases: ['sajek', 'সাজেক']),

  // ── Tea, haor, forest and rivers ────────────────────────────────────
  DestinationPreset(
      id: 'sreemangal',
      nameEn: 'Sreemangal',
      nameBn: 'শ্রীমঙ্গল',
      lat: 24.3065,
      lng: 91.7296,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['srimangal', 'sri mangal']),
  DestinationPreset(
      id: 'lawachara',
      nameEn: 'Lawachara National Park',
      nameBn: 'লাউয়াছড়া জাতীয় উদ্যান',
      lat: 24.3220,
      lng: 91.7860,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['lawachara']),
  DestinationPreset(
      id: 'jaflong',
      nameEn: 'Jaflong',
      nameBn: 'জাফলং',
      lat: 25.1630,
      lng: 92.0175,
      kind: TourType.nature,
      region: 'Sylhet'),
  DestinationPreset(
      id: 'ratargul',
      nameEn: 'Ratargul Swamp Forest',
      nameBn: 'রাতারগুল সোয়াম্প ফরেস্ট',
      lat: 25.0105,
      lng: 91.9330,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['ratargul']),
  DestinationPreset(
      id: 'sada_pathor',
      nameEn: 'Bholaganj Sada Pathor',
      nameBn: 'ভোলাগঞ্জ সাদা পাথর',
      lat: 25.2390,
      lng: 91.8360,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['sada pathor', 'bholaganj']),
  DestinationPreset(
      id: 'bisnakandi',
      nameEn: 'Bisnakandi',
      nameBn: 'বিছনাকান্দি',
      lat: 25.1820,
      lng: 91.8890,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['bichanakandi']),
  DestinationPreset(
      id: 'tanguar_haor',
      nameEn: 'Tanguar Haor',
      nameBn: 'টাঙ্গুয়ার হাওর',
      lat: 25.1358,
      lng: 91.0650,
      kind: TourType.nature,
      region: 'Sylhet',
      aliases: ['tanguar', 'tangua']),
  DestinationPreset(
      id: 'sundarbans',
      nameEn: 'Sundarbans',
      nameBn: 'সুন্দরবন',
      lat: 22.4250,
      lng: 89.5880,
      kind: TourType.nature,
      region: 'Khulna',
      aliases: ['sundarban', 'karamjal', 'katka']),
  DestinationPreset(
      id: 'mongla',
      nameEn: 'Mongla',
      nameBn: 'মোংলা',
      lat: 22.4744,
      lng: 89.6000,
      kind: TourType.nature,
      region: 'Khulna'),

  // ── Heritage ───────────────────────────────────────────────────────────
  DestinationPreset(
      id: 'bagerhat',
      nameEn: 'Bagerhat (Sixty Dome Mosque)',
      nameBn: 'বাগেরহাট (ষাট গম্বুজ মসজিদ)',
      lat: 22.6744,
      lng: 89.7417,
      kind: TourType.heritage,
      region: 'Khulna',
      aliases: ['bagerhat', 'sixty dome', 'ষাট গম্বুজ']),
  DestinationPreset(
      id: 'sonargaon',
      nameEn: 'Sonargaon (Panam City)',
      nameBn: 'সোনারগাঁও (পানাম নগর)',
      lat: 23.6470,
      lng: 90.6100,
      kind: TourType.heritage,
      region: 'Dhaka',
      aliases: ['sonargaon', 'panam']),
  DestinationPreset(
      id: 'mahasthangarh',
      nameEn: 'Mahasthangarh',
      nameBn: 'মহাস্থানগড়',
      lat: 24.9600,
      lng: 89.3460,
      kind: TourType.heritage,
      region: 'Rajshahi'),
  DestinationPreset(
      id: 'paharpur',
      nameEn: 'Paharpur Buddhist Vihara',
      nameBn: 'পাহাড়পুর বৌদ্ধ বিহার',
      lat: 25.0310,
      lng: 88.9770,
      kind: TourType.heritage,
      region: 'Rajshahi',
      aliases: ['paharpur']),
  DestinationPreset(
      id: 'kantajew',
      nameEn: 'Kantajew Temple (Dinajpur)',
      nameBn: 'কান্তজীর মন্দির (দিনাজপুর)',
      lat: 25.7930,
      lng: 88.6670,
      kind: TourType.heritage,
      region: 'Rangpur',
      aliases: ['kantajew', 'kantaji', 'dinajpur']),
  DestinationPreset(
      id: 'mainamati',
      nameEn: 'Mainamati',
      nameBn: 'ময়নামতি',
      lat: 23.4310,
      lng: 91.1360,
      kind: TourType.heritage,
      region: 'Chattogram'),
  DestinationPreset(
      id: 'puran_dhaka',
      nameEn: 'Old Dhaka',
      nameBn: 'পুরান ঢাকা',
      lat: 23.7104,
      lng: 90.4074,
      kind: TourType.heritage,
      region: 'Dhaka',
      aliases: ['old dhaka', 'puran dhaka', 'lalbagh']),
];

/// The catalog entry for [id], if any.
DestinationPreset? presetById(String? id) {
  if (id == null) return null;
  for (final p in kDestinationCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

/// The best catalog match for a place someone typed, such as "Cox's Bazar
/// trip" or "ঢাকা". Longer names win, so "Inani Beach" beats "Cox's Bazar"
/// when both appear.
DestinationPreset? presetForName(String text) {
  DestinationPreset? best;
  var bestLength = 0;
  for (final p in kDestinationCatalog) {
    if (!p.matches(text)) continue;
    final length = p.nameEn.length;
    if (length > bestLength) {
      best = p;
      bestLength = length;
    }
  }
  return best;
}
