import '../models/tour_activity_models.dart';
import 'route_engine.dart';

/// A well-known stop on a popular route, offered to the tour leader. Adding
/// one makes it an ordinary checkpoint the group can edit or remove.
class SuggestedStop {
  const SuggestedStop({
    required this.name,
    required this.km,
    required this.kind,
    required this.lat,
    required this.lng,
    this.highlight = '',
  });

  final String name;

  /// Approximate road km from Dhaka.
  final int km;
  final CheckpointKind kind;
  final double lat;
  final double lng;
  final String highlight;
}

/// Popular road stops from Dhaka, by destination catalog id.
const Map<String, List<SuggestedStop>> _fromDhaka = {
  'coxs_bazar': _coxsBazar,
  'inani': _coxsBazar,
  'teknaf': _coxsBazar,
  'bandarban': [
    SuggestedStop(
        name: 'কাঁচপুর সেতু (Kanchpur Bridge)',
        km: 15,
        kind: CheckpointKind.toll,
        lat: 23.7046,
        lng: 90.5233),
    SuggestedStop(
        name: 'পদুয়ার বাজার বিশ্বরোড, কুমিল্লা (Paduar Bazar)',
        km: 100,
        kind: CheckpointKind.food,
        lat: 23.4287,
        lng: 91.1783,
        highlight: 'হাইওয়ে রেস্তোরাঁ ও নামাজের বিরতি'),
    SuggestedStop(
        name: 'চট্টগ্রাম সিটি গেইট (Chattogram City Gate)',
        km: 250,
        kind: CheckpointKind.custom,
        lat: 22.3789,
        lng: 91.7765),
    SuggestedStop(
        name: 'কেরানীহাট মোড় (Keranihat)',
        km: 300,
        kind: CheckpointKind.food,
        lat: 22.0945,
        lng: 92.0721,
        highlight: 'পাহাড়ি রাস্তায় ওঠার আগে বিরতি'),
  ],
  'nilgiri': [
    SuggestedStop(
        name: 'কেরানীহাট মোড় (Keranihat)',
        km: 300,
        kind: CheckpointKind.food,
        lat: 22.0945,
        lng: 92.0721),
    SuggestedStop(
        name: 'বান্দরবান শহর (Bandarban Town)',
        km: 320,
        kind: CheckpointKind.custom,
        lat: 22.1953,
        lng: 92.2184,
        highlight: 'চাঁদের গাড়ি বুকিং'),
  ],
  'sajek': [
    SuggestedStop(
        name: 'কুমিল্লা ময়নামতি / পদুয়ার বাজার',
        km: 100,
        kind: CheckpointKind.food,
        lat: 23.4287,
        lng: 91.1783),
    SuggestedStop(
        name: 'খাগড়াছড়ি শহর (Khagrachhari Town)',
        km: 270,
        kind: CheckpointKind.food,
        lat: 23.1118,
        lng: 91.9847,
        highlight: 'নাস্তা ও চাঁদের গাড়ি'),
    SuggestedStop(
        name: 'দীঘিনালা সেনা এসকর্ট পয়েন্ট (Dighinala escort)',
        km: 290,
        kind: CheckpointKind.checkpost,
        lat: 23.2562,
        lng: 92.0583,
        highlight: 'সকাল ও দুপুরের এসকর্ট কনভয়ের সময় মিলিয়ে পৌঁছান'),
    SuggestedStop(
        name: 'বাঘাইহাট বাজার (Baghaihat)',
        km: 315,
        kind: CheckpointKind.checkpost,
        lat: 23.3421,
        lng: 92.1782),
  ],
  'khagrachhari': [
    SuggestedStop(
        name: 'কুমিল্লা পদুয়ার বাজার',
        km: 100,
        kind: CheckpointKind.food,
        lat: 23.4287,
        lng: 91.1783),
    SuggestedStop(
        name: 'ফেনী মহিপাল (Feni Mohipal)',
        km: 160,
        kind: CheckpointKind.fuel,
        lat: 23.0159,
        lng: 91.3976),
  ],
  'rangamati': [
    SuggestedStop(
        name: 'কুমিল্লা পদুয়ার বাজার',
        km: 100,
        kind: CheckpointKind.food,
        lat: 23.4287,
        lng: 91.1783),
    SuggestedStop(
        name: 'চট্টগ্রাম অক্সিজেন মোড় (Oxygen)',
        km: 255,
        kind: CheckpointKind.custom,
        lat: 22.4040,
        lng: 91.8180),
  ],
  'sylhet': _sylhet,
  'jaflong': _sylhet,
  'ratargul': _sylhet,
  'sada_pathor': _sylhet,
  'bisnakandi': _sylhet,
  'sreemangal': [
    SuggestedStop(
        name: 'ভৈরব মেঘনা সেতু ও উজানভাটি (Bhairab)',
        km: 85,
        kind: CheckpointKind.food,
        lat: 24.0512,
        lng: 90.9832,
        highlight: 'সকালের নাস্তা ও চা'),
    SuggestedStop(
        name: 'শায়েস্তাগঞ্জ (Shayestaganj)',
        km: 165,
        kind: CheckpointKind.fuel,
        lat: 24.2797,
        lng: 91.4578),
  ],
  'kuakata': [
    SuggestedStop(
        name: 'পদ্মা সেতু টোল প্লাজা (Padma Bridge)',
        km: 40,
        kind: CheckpointKind.toll,
        lat: 23.4475,
        lng: 90.2647,
        highlight: '৬.১৫ কিমি পদ্মা সেতু পারাপার'),
    SuggestedStop(
        name: 'ভাঙ্গা গোলচত্বর (Bhanga)',
        km: 85,
        kind: CheckpointKind.fuel,
        lat: 23.3830,
        lng: 89.9930),
    SuggestedStop(
        name: 'বরিশাল নথুল্লাবাদ (Barishal)',
        km: 170,
        kind: CheckpointKind.food,
        lat: 22.7100,
        lng: 90.3530),
    SuggestedStop(
        name: 'পায়রা সেতু, লেবুখালী (Payra Bridge)',
        km: 210,
        kind: CheckpointKind.viewpoint,
        lat: 22.4832,
        lng: 90.3341),
  ],
  'sundarbans': [
    SuggestedStop(
        name: 'পদ্মা সেতু টোল প্লাজা (Padma Bridge)',
        km: 40,
        kind: CheckpointKind.toll,
        lat: 23.4475,
        lng: 90.2647),
    SuggestedStop(
        name: 'ভাঙ্গা গোলচত্বর (Bhanga)',
        km: 85,
        kind: CheckpointKind.food,
        lat: 23.3830,
        lng: 89.9930),
    SuggestedStop(
        name: 'মোংলা বন্দর ও লঞ্চ ঘাট (Mongla)',
        km: 210,
        kind: CheckpointKind.ferry,
        lat: 22.4744,
        lng: 89.6000,
        highlight: 'বন বিভাগের অনুমতি ও গাইড সঙ্গে নিন'),
  ],
  'mongla': [
    SuggestedStop(
        name: 'পদ্মা সেতু টোল প্লাজা (Padma Bridge)',
        km: 40,
        kind: CheckpointKind.toll,
        lat: 23.4475,
        lng: 90.2647),
    SuggestedStop(
        name: 'ভাঙ্গা গোলচত্বর (Bhanga)',
        km: 85,
        kind: CheckpointKind.food,
        lat: 23.3830,
        lng: 89.9930),
  ],
};

const _coxsBazar = [
  SuggestedStop(
      name: 'কাঁচপুর সেতু (Kanchpur Bridge)',
      km: 15,
      kind: CheckpointKind.toll,
      lat: 23.7046,
      lng: 90.5233),
  SuggestedStop(
      name: 'মেঘনা-গোমতী সেতু, দাউদকান্দি (Daudkandi)',
      km: 45,
      kind: CheckpointKind.toll,
      lat: 23.5420,
      lng: 90.6830),
  SuggestedStop(
      name: 'পদুয়ার বাজার বিশ্বরোড, কুমিল্লা (Paduar Bazar)',
      km: 100,
      kind: CheckpointKind.food,
      lat: 23.4287,
      lng: 91.1783,
      highlight: 'রসমালাই, নাস্তা ও নামাজের বিরতি'),
  SuggestedStop(
      name: 'ফেনী মহিপাল (Feni Mohipal)',
      km: 160,
      kind: CheckpointKind.fuel,
      lat: 23.0159,
      lng: 91.3976),
  SuggestedStop(
      name: 'চট্টগ্রাম সিটি গেইট (Chattogram City Gate)',
      km: 250,
      kind: CheckpointKind.custom,
      lat: 22.3789,
      lng: 91.7765),
  SuggestedStop(
      name: 'চকরিয়া (Chakaria)',
      km: 330,
      kind: CheckpointKind.food,
      lat: 21.7900,
      lng: 92.0780,
      highlight: 'শেষ বড় বিরতি'),
];

const _sylhet = [
  SuggestedStop(
      name: 'ভৈরব মেঘনা সেতু ও উজানভাটি (Bhairab)',
      km: 85,
      kind: CheckpointKind.food,
      lat: 24.0512,
      lng: 90.9832,
      highlight: 'সকালের নাস্তা ও চা'),
  SuggestedStop(
      name: 'শায়েস্তাগঞ্জ (Shayestaganj)',
      km: 165,
      kind: CheckpointKind.fuel,
      lat: 24.2797,
      lng: 91.4578),
  SuggestedStop(
      name: 'শেরপুর, মৌলভীবাজার (Sherpur)',
      km: 205,
      kind: CheckpointKind.prayer,
      lat: 24.6330,
      lng: 91.6830),
];

/// Suggested stops for [leg]: offered when it runs by road from Dhaka to a
/// destination with known stops. Empty otherwise.
List<SuggestedStop> suggestedStopsFor(RouteLeg leg, {String? toPresetId}) {
  if (!leg.from.isOrigin) return const [];
  final from = leg.from.name.toLowerCase();
  if (!(from.contains('dhaka') || from.contains('ঢাকা'))) return const [];
  return _fromDhaka[toPresetId] ?? const [];
}
