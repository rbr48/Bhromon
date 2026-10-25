import 'package:flutter/material.dart';
import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_activity_models.dart';

class HighwayMilestone {
  final String id;
  final String name;
  final String nameEn;
  final int kmFromStart;
  final double lat;
  final double lng;
  final String estDuration;
  final String highlight;
  final String details;
  final List<String> amenities;
  final String iconEmoji;

  const HighwayMilestone({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.kmFromStart,
    required this.lat,
    required this.lng,
    required this.estDuration,
    required this.highlight,
    required this.details,
    required this.amenities,
    required this.iconEmoji,
  });
}

class JourneyTrackerScreen extends StatefulWidget {
  final String tourId;

  const JourneyTrackerScreen({super.key, required this.tourId});

  @override
  State<JourneyTrackerScreen> createState() => _JourneyTrackerScreenState();
}

class _JourneyTrackerScreenState extends State<JourneyTrackerScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  Position? _currentPosition;
  int _activeFilterIndex = 0; // 0: All, 1: Rest/Food, 2: Prayer, 3: Fuel
  // Stops that group members added; shared by everyone on the tour.
  List<RouteCheckpoint> _checkpoints = const [];
  StreamSubscription<List<RouteCheckpoint>>? _checkpointSub;

  /// The curated stop lists were measured from Dhaka. From any other origin
  /// they would be wrong, so they are hidden.
  bool get _isDhakaOrigin {
    if (_tourGroup == null) return true;
    final origin = _tourGroup!.originCity.toLowerCase();
    return origin.contains('dhaka') || origin.contains('ঢাকা');
  }

  @override
  void initState() {
    super.initState();
    _loadGroup();
    _fetchGps();
    _checkpointSub = _repository.watchCheckpoints(widget.tourId).listen(
      (cps) {
        if (mounted) setState(() => _checkpoints = cps);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _checkpointSub?.cancel();
    super.dispose();
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) setState(() => _tourGroup = g);
  }

  Future<void> _fetchGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _openLocationOnMap(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<HighwayMilestone> _getRouteMilestones() {
    final dest = _tourGroup?.destination.toLowerCase() ?? '';
    final origin = _tourGroup?.originCity ?? 'রংপুর';

    List<HighwayMilestone> baseList = const [];

    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      baseList = [
        HighwayMilestone(
          id: 'SAJEK_1',
          name: '$origin জিরো পয়েন্ট (যাত্রার শুরু)',
          nameEn: '$origin Starting Point',
          kmFromStart: 0,
          lat: 23.8103,
          lng: 90.4125,
          estDuration: '০০:০০ ঘণ্টা',
          highlight: 'নিরাপদ পাহাড়ি ভ্রমণের দোয়া ও শুভ সূচনা',
          details: 'চাঁদের গাড়ি বা বাসে আসন গ্রহণ ও মালামাল সুরক্ষা।',
          amenities: const ['বাস ডিপো', 'চা ও নাস্তা', 'নামাজ'],
          iconEmoji: '🚙',
        ),
        const HighwayMilestone(
          id: 'SAJEK_2',
          name: 'খাগড়াছড়ি শহর ও রিছাং ঝর্ণা মোড়',
          nameEn: 'Khagrachhari Town & Richang',
          kmFromStart: 250,
          lat: 23.1118,
          lng: 91.9847,
          estDuration: '০৬:০০ ঘণ্টা',
          highlight: 'পাহাড়ি উপত্যকার প্রবেশদ্বার ও ঝর্ণা পয়েন্ট',
          details: 'হালকা নাস্তা, রিফ্রেশমেন্ট ও চাঁদের গাড়ির তেল চেক।',
          amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'নামাজঘর', 'পাম্প'],
          iconEmoji: '🏞️',
        ),
        const HighwayMilestone(
          id: 'SAJEK_3',
          name: 'দীঘিনালা সেনা ক্যাম্প ও এসকর্ট পয়েন্ট',
          nameEn: 'Dighinala Army Escort Checkpost',
          kmFromStart: 285,
          lat: 23.2562,
          lng: 92.0583,
          estDuration: '০৭:৩০ ঘণ্টা',
          highlight: 'নিরাপত্তা এসকর্ট ও সেনাবাহিনীর ছাড়পত্র',
          details:
              'সকাল ১০টা বা দুপুর ২টার এসকর্ট কনভয়ে সাজেকের পাহাড়ে প্রবেশ।',
          amenities: ['সেনা চেকপোস্ট', 'নিরাপত্তা ও সহায়তা'],
          iconEmoji: '🛡️',
        ),
        const HighwayMilestone(
          id: 'SAJEK_4',
          name: 'বাঘাইহাট ও কাসালং নদী ব্রিজ',
          nameEn: 'Baghaihat & Kasalong Bridge',
          kmFromStart: 305,
          lat: 23.3421,
          lng: 92.1782,
          estDuration: '০৮:৩০ ঘণ্টা',
          highlight: 'মেঘের কাছাকাছি পাহাড়ি আঁকাবাঁকা রাস্তা',
          details: 'রোলার-কোস্টারের মতো পাহাড়ি উঁচু-নিচু রোমাঞ্চকর পথ।',
          amenities: ['ভিউ পয়েন্ট', 'চা দোকান'],
          iconEmoji: '⛰️',
        ),
        const HighwayMilestone(
          id: 'SAJEK_5',
          name: 'সাজেক ভ্যালি (রুইলুই পাড়া ও কংলাক)',
          nameEn: 'Sajek Valley (Ruilui & Konglak)',
          kmFromStart: 340,
          lat: 23.3828,
          lng: 92.2938,
          estDuration: '০৯:৩০ ঘণ্টা',
          highlight: 'মেঘের বাড়ি সাজেক ও কংলাক পাহাড় চূড়া',
          details:
              'রিসোর্টে চেক-ইন, কটেজে বসে সূর্যাস্ত দেখা ও মেঘের ভেলা উপভোগ।',
          amenities: ['রিসোর্ট', 'ক্যাফে', 'হেলিপ্যাড', 'মার্কেট'],
          iconEmoji: '☁️',
        ),
      ];
    } else if (dest.contains('sylhet') ||
        dest.contains('সিলেট') ||
        dest.contains('sreemangal')) {
      baseList = [
        HighwayMilestone(
          id: 'SYL_1',
          name: '$origin কাউন্টার (যাত্রা শুরু)',
          nameEn: '$origin Departure Counter',
          kmFromStart: 0,
          lat: 23.8103,
          lng: 90.4125,
          estDuration: '০০:০০ ঘণ্টা',
          highlight: 'সিলেট অভিমুখে হাইওয়ে এক্সপ্রেস যাত্রা',
          details: 'যাত্রার প্রাক্কালে শুভকামনা ও বাসে আরোহণ।',
          amenities: const ['বাস টার্মিনাল', 'চা', 'নামাজ'],
          iconEmoji: '🚌',
        ),
        const HighwayMilestone(
          id: 'SYL_2',
          name: 'ভৈরব মেঘনা নদী সেতু ও উজানভাটি',
          nameEn: 'Bhairab Meghna Bridge & Ujanbhati',
          kmFromStart: 85,
          lat: 24.0512,
          lng: 90.9832,
          estDuration: '০২:০০ ঘণ্টা',
          highlight: 'মেঘনা নদীর নৈসর্গিক ভিউ ও ঐতিহ্যবাহী খাবার',
          details: 'উজানভাটি হাইওয়ে রেস্তোরাঁয় সকালের গরম পরোটা ও স্পেশাল চা।',
          amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'নামাজঘর', 'পাম্প'],
          iconEmoji: '🍲',
        ),
        const HighwayMilestone(
          id: 'SYL_3',
          name: 'মাধবপুর লেক ও শ্রীমঙ্গল চা বাগান জোন',
          nameEn: 'Sreemangal Tea Estates Valley',
          kmFromStart: 180,
          lat: 24.3065,
          lng: 91.7296,
          estDuration: '০৪:৩০ ঘণ্টা',
          highlight: 'সবুজ চা পাতার মখমল পাহাড় ও সাত রঙের চা',
          details: 'চা বাগানের অপরূপ স্নিগ্ধ সমারোহ ও ছবি তোলার সেরা স্পট।',
          amenities: ['চা বাগান', 'ভিউ পয়েন্ট', 'ওয়াশরুম'],
          iconEmoji: '🍃',
        ),
        const HighwayMilestone(
          id: 'SYL_4',
          name: 'সিলেট শহর ও শাহজালাল (র.) মাজার',
          nameEn: 'Sylhet City & Hazrat Shahjalal Dargah',
          kmFromStart: 250,
          lat: 24.8949,
          lng: 91.8687,
          estDuration: '০৬:০০ ঘণ্টা',
          highlight: 'ঐতিহ্যবাহী পুণ্যভূমি সিলেট ও সাতকড়া বিফ',
          details:
              'হোটেল চেক-ইন, ফ্রেশ হওয়া এবং শহরের বিখ্যাত খাবারের স্বাদ গ্রহণ।',
          amenities: ['হোটেল', 'মাজার', 'রেস্তোরাঁ', 'শপিং'],
          iconEmoji: '🕌',
        ),
        const HighwayMilestone(
          id: 'SYL_5',
          name: 'জাফলং ও ভোলাগঞ্জ সাদা পাথর জিরো পয়েন্ট',
          nameEn: 'Jaflong & Sada Pathor Zero Point',
          kmFromStart: 310,
          lat: 25.1634,
          lng: 92.0189,
          estDuration: '০৮:০০ ঘণ্টা',
          highlight: 'মেঘালয় পাহাড়ের পাদদেশে স্বচ্ছ জল ও সাদা পাথর',
          details: 'নৌকায় করে সাদা পাথরে স্নান এবং মায়াবী ঝর্ণা দর্শন।',
          amenities: ['নৌকা ঘাট', 'ঝর্ণা', 'পাথুরে নদী'],
          iconEmoji: '💎',
        ),
      ];
    } else if (dest.contains('bandarban') || dest.contains('বান্দরবান')) {
      baseList = [
        HighwayMilestone(
          id: 'BAN_1',
          name: '$origin কাউন্টার (যাত্রা শুরু)',
          nameEn: '$origin Starting Point',
          kmFromStart: 0,
          lat: 23.8103,
          lng: 90.4125,
          estDuration: '০০:০০ ঘণ্টা',
          highlight: 'বান্দরবান পাহাড় ও ঝর্ণা অভিযানের শুভ সূচনা',
          details: 'যাত্রার প্রারম্ভিক চেক ও বাসে আসন গ্রহণ।',
          amenities: const ['টার্মিনাল', 'চা', 'নামাজ'],
          iconEmoji: '🚌',
        ),
        const HighwayMilestone(
          id: 'BAN_2',
          name: 'চট্টগ্রাম সিটি গেইট ও কর্ণফুলী শাহ আমানত সেতু',
          nameEn: 'Chittagong City Gate & Karnaphuli',
          kmFromStart: 250,
          lat: 22.3384,
          lng: 91.8317,
          estDuration: '০৫:৩০ ঘণ্টা',
          highlight: 'বাণিজ্যিক রাজধানী অতিক্রম ও কর্ণফুলী পারাপার',
          details: 'হাইওয়ে রিফ্রেশমেন্ট ও পাহাড়ি রোডের জন্য প্রস্তুতি।',
          amenities: ['হাইওয়ে রেস্তোরাঁ', 'ওয়াশরুম', 'পাম্প'],
          iconEmoji: '🌉',
        ),
        const HighwayMilestone(
          id: 'BAN_3',
          name: 'কেরানীহাট ও বান্দরবান প্রবেশ মোড়',
          nameEn: 'Keranihat Hill Entry Point',
          kmFromStart: 310,
          lat: 22.0945,
          lng: 92.0721,
          estDuration: '০৭:০০ ঘণ্টা',
          highlight: 'পাহাড়ি আঁকাবাঁকা ও নৈসর্গিক সবুজ উপত্যকা',
          details: 'পাহাড়ে প্রবেশের চমৎকার অনুভূতি ও শীতল বাতাস।',
          amenities: ['পাহাড়ি বাজার', 'ওয়াশরুম'],
          iconEmoji: '⛰️',
        ),
        const HighwayMilestone(
          id: 'BAN_4',
          name: 'বান্দরবান শহর ও মেঘলা পর্যটন কমপ্লেক্স',
          nameEn: 'Bandarban Town & Meghla',
          kmFromStart: 335,
          lat: 22.1953,
          lng: 92.2184,
          estDuration: '০৮:০০ ঘণ্টা',
          highlight: 'ঝুলন্ত সেতু ও পাহাড়ি লেকের সৌন্দর্য',
          details: 'রিসোর্টে চেক-ইন ও চাঁদের গাড়ি বুকিং।',
          amenities: ['হোটেল', 'রেস্তোরাঁ', 'মার্কেট'],
          iconEmoji: '🏞️',
        ),
        const HighwayMilestone(
          id: 'BAN_5',
          name: 'নীলাচল ও নীলগিরি মেঘের স্বর্গরাজ্য',
          nameEn: 'Nilachal & Nilgiri Peak',
          kmFromStart: 380,
          lat: 21.9189,
          lng: 92.3364,
          estDuration: '১০:০০ ঘণ্টা',
          highlight: 'সমুদ্রপৃষ্ঠ থেকে ২৪০০ ফুট উঁচুতে মেঘ ছোঁয়ার রোমাঞ্চ',
          details: 'নীলগিরির চূড়ায় সূর্যোদয় ও সূর্যাস্তের অপার্থিব রূপ।',
          amenities: ['ভিউ পয়েন্ট', 'সেনা ক্যাফে', 'কটেজ'],
          iconEmoji: '☁️',
        ),
      ];
    } else if (dest.contains('kuakata') || dest.contains('কুয়াকাটা')) {
      baseList = [
        HighwayMilestone(
          id: 'KUA_1',
          name: '$origin কাউন্টার (যাত্রা শুরু)',
          nameEn: '$origin Starting Point',
          kmFromStart: 0,
          lat: 23.8103,
          lng: 90.4125,
          estDuration: '০০:০০ ঘণ্টা',
          highlight: 'পদ্মা সেতু হয়ে সাগরকন্যা কুয়াকাটা যাত্রা',
          details: 'এক্সপ্রেসওয়ে ধরে যাত্রা শুরু।',
          amenities: const ['টার্মিনাল', 'চা', 'নামাজ'],
          iconEmoji: '🚌',
        ),
        const HighwayMilestone(
          id: 'KUA_2',
          name: 'পদ্মা বহুমুখী সেতু ও ভাঙ্গা এক্সপ্রেসওয়ে',
          nameEn: 'Padma Multipurpose Bridge & Bhanga',
          kmFromStart: 60,
          lat: 23.4475,
          lng: 90.2647,
          estDuration: '০১:১৫ ঘণ্টা',
          highlight: 'জাতীয় গৌরবের ৬.১৫ কিমি পদ্মা সেতু পারাপার',
          details:
              'দক্ষিণাঞ্চলের স্বপ্নিল এক্সপ্রেসওয়ে দিয়ে দ্রুতিতে ছুটে চলা।',
          amenities: ['টোল প্লাজা', 'ভিউ পয়েন্ট'],
          iconEmoji: '🌉',
        ),
        const HighwayMilestone(
          id: 'KUA_3',
          name: 'পায়রা সেতু (লেবুখালী) ও পটুয়াখালী',
          nameEn: 'Payra Bridge & Patuakhali',
          kmFromStart: 210,
          lat: 22.4832,
          lng: 90.3341,
          estDuration: '০৪:৩০ ঘণ্টা',
          highlight: 'পায়রা নদীর সুবিশাল নান্দনিক সেতু',
          details: 'হাইওয়ে রিফ্রেশমেন্ট ও তাজা ইলিশের স্বাদ।',
          amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'পাম্প'],
          iconEmoji: '🌊',
        ),
        const HighwayMilestone(
          id: 'KUA_4',
          name: 'কুয়াকাটা সৈকত সূর্যোদয় ও সূর্যাস্ত পয়েন্ট',
          nameEn: 'Kuakata Beach Zero Point',
          kmFromStart: 280,
          lat: 21.8167,
          lng: 90.1167,
          estDuration: '০৬:০০ ঘণ্টা',
          highlight: 'একই সৈকত থেকে সূর্যোদয় ও সূর্যাস্ত দর্শন',
          details: 'হোটেল চেক-ইন, ঝাউবন ও লাল কাঁকড়ার চরে ঘুরে বেড়ানো।',
          amenities: ['হোটেল', 'সৈকত', 'রেস্তোরাঁ', 'মার্কেট'],
          iconEmoji: '🌅',
        ),
      ];
    } else if (dest.contains('cox')) {
      // Cox's Bazar route. Other destinations get no curated stops.
      // Default: Comprehensive Cox's Bazar / Universal Route
      baseList = [
        HighwayMilestone(
          id: 'START_01',
          name: '$origin জিরো পয়েন্ট (যাত্রার শুভ সূচনা)',
          nameEn: '$origin Starting Zero Point',
          kmFromStart: 0,
          lat: 25.7439,
          lng: 89.2752,
          estDuration: '০০:০০ ঘণ্টা',
          highlight: 'যাত্রার শুভ সূচনা ও ভ্রমণ দোয়া',
          details:
              'পরিবারের সকলের বাসে আসন গ্রহণ, লাগেজ চেকিং ও নিরাপদ ভ্রমণের শুভ দোয়া।',
          amenities: const ['বাস ডিপো', 'চা ও কফি', 'নামাজ'],
          iconEmoji: '🚌',
        ),
        const HighwayMilestone(
          id: 'BOGRA_SHERPUR',
          name: 'বগুড়া শেরপুর (ফুড ভিলেজ প্লাস)',
          nameEn: 'Sherpur, Bogra',
          kmFromStart: 110,
          lat: 24.6738,
          lng: 89.4187,
          estDuration: '০২:১৫ ঘণ্টা',
          highlight: 'শেরপুরের বিখ্যাত দই ও রাতের হালকা নাস্তা',
          details:
              'ফুড ভিলেজে হাইওয়ে বিরতি, পরিষ্কার ওয়াশরুম এবং স্পেশাল চা ও মিষ্টি দই।',
          amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'নামাজঘর', 'এটিএম'],
          iconEmoji: '🍲',
        ),
        const HighwayMilestone(
          id: 'JAMUNA_BRIDGE',
          name: 'বঙ্গবন্ধু যমুনা বহুমুখী সেতু',
          nameEn: 'Jamuna Bridge',
          kmFromStart: 180,
          lat: 24.3985,
          lng: 89.7828,
          estDuration: '০৩:৪৫ ঘণ্টা',
          highlight: 'যমুনা নদীর নৈসর্গিক রূপ ও সেতু পারাপার',
          details: 'পশ্চিম টোল প্লাজা অতিক্রম করে ঐতিহ্যবাহী যমুনা পারাপার।',
          amenities: ['টোল প্লাজা', 'ভিউ পয়েন্ট'],
          iconEmoji: '🌉',
        ),
        const HighwayMilestone(
          id: 'KANCHPUR_MEGHNA',
          name: 'কাঁচপুর ও মেঘনা ঘাট (হাইওয়ে ইন)',
          nameEn: 'Kanchpur / Meghna Ghat',
          kmFromStart: 330,
          lat: 23.5937,
          lng: 90.6128,
          estDuration: '০৭:১৫ ঘণ্টা',
          highlight: 'দ্বিতীয় মেঘনা সেতু ও হাইওয়ে কফি ব্রেক',
          details: 'মেঘনা ব্রিজে ভোররাতের মৃদু বাতাস ও তাজা কফি।',
          amenities: ['হাইওয়ে ইন', 'ওয়াশরুম', 'নামাজঘর'],
          iconEmoji: '☕',
        ),
        const HighwayMilestone(
          id: 'PADUAR_BAZAR',
          name: 'পদুয়ার বাজার বিশ্বরোড, কুমিল্লা',
          nameEn: 'Paduar Bazar, Cumilla',
          kmFromStart: 420,
          lat: 23.4287,
          lng: 91.1783,
          estDuration: '০৯:১৫ ঘণ্টা',
          highlight: 'কুমিল্লার বিখ্যাত রসমালাই ও সকালের নাস্তা',
          details:
              'মাতৃভাণ্ডারের খাঁটি রসমালাইয়ের স্বাদ ও ফজরের নামাজের বিরতি।',
          amenities: ['রসমালাই', 'রেস্তোরাঁ', 'নামাজঘর', 'পাম্প'],
          iconEmoji: '🍮',
        ),
        const HighwayMilestone(
          id: 'CHITTAGONG_GATE',
          name: 'চট্টগ্রাম সিটি গেইট ও অলংকার মোড়',
          nameEn: 'Chittagong City Gate',
          kmFromStart: 580,
          lat: 22.3789,
          lng: 91.7765,
          estDuration: '১২:৩০ ঘণ্টা',
          highlight: 'বন্দরনগরী চট্টগ্রাম আগমন ও পাহাড়ের হাতছানি',
          details:
              'একে খান মোড় হয়ে চট্টগ্রাম বাইপাস রোড ধরে সরাসরি কক্সবাজারমুখী।',
          amenities: ['সিটি বাইপাস', 'ট্রাফিক সহায়তা'],
          iconEmoji: '🏙️',
        ),
        HighwayMilestone(
          id: 'DEST_FINAL',
          name:
              '${_tourGroup?.destination ?? "কক্সবাজার"} ডলফিন মোড় ও হোটেল এরিয়া',
          nameEn: '${_tourGroup?.destination ?? "Coxs Bazar"} Dolphin Point',
          kmFromStart: 820,
          lat: 21.4326,
          lng: 91.9774,
          estDuration: '১৬:০০ ঘণ্টা',
          highlight: 'গন্তব্যে সফল আগমন ও ভ্রমণ শুভ সমাপ্তি',
          details: 'হোটেলে চেক-ইন, ফ্রেশ হওয়া এবং সুন্দর মুহূর্তের সূচনা।',
          amenities: const ['হোটেল', 'সৈকত/স্পট', 'রেস্তোরাঁ', 'মার্কেট'],
          iconEmoji: '🏖️',
        ),
      ];
    }

    final combined = List<HighwayMilestone>.from(
        _isDhakaOrigin ? baseList : const <HighwayMilestone>[])
      ..addAll(_checkpoints.map(_milestoneFromCheckpoint));
    return combined;
  }

  HighwayMilestone _milestoneFromCheckpoint(RouteCheckpoint c) {
    return HighwayMilestone(
      id: c.id,
      name: c.name,
      nameEn: c.name,
      kmFromStart: c.kmFromStart,
      lat: c.lat ?? 0,
      lng: c.lng ?? 0,
      estDuration: 'ট্যুর সদস্য যুক্ত করেছেন',
      highlight: c.highlight.isEmpty ? 'চেকপয়েন্ট' : c.highlight,
      details: 'এই স্টপটি ট্যুরের একজন সদস্য যুক্ত করেছেন।',
      amenities: const ['কাস্টম স্টপ'],
      iconEmoji: '📍',
    );
  }

  /// Whether a stop passes the active filter (the same rules the timeline uses).
  bool _matchesFilter(HighwayMilestone m) {
    if (_activeFilterIndex == 1 &&
        !m.amenities.any((a) =>
            a.contains('রেস্তোরাঁ') ||
            a.contains('নাস্তা') ||
            a.contains('খাবার') ||
            a.contains('ক্যাফে'))) {
      return false;
    }
    if (_activeFilterIndex == 2 &&
        !m.amenities.any((a) => a.contains('নামাজ'))) {
      return false;
    }
    if (_activeFilterIndex == 3 &&
        !m.amenities.any((a) =>
            a.contains('পাম্প') || a.contains('তেল') || a.contains('ফুয়েল'))) {
      return false;
    }

    return true;
  }

  /// Adds a stop for everyone on the tour. The stop's place is not the
  /// adder's GPS position, so no coordinates are stored.
  void _showAddMilestoneDialog() {
    final nameCtrl = TextEditingController();
    final kmCtrl = TextEditingController();
    final highlightCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF142428),
          title: const Text('নতুন চেকপয়েন্ট যোগ করুন',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'স্টপ বা চেকপয়েন্টের নাম',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: kmCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'শুরু থেকে দূরত্ব (কি.মি.)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: highlightCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'বিশেষ আকর্ষণ বা হাইলাইট',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final km = int.tryParse(kmCtrl.text.trim());
                if (name.isEmpty || km == null || km < 0) return;
                Navigator.pop(ctx);
                try {
                  await _repository.addCheckpoint(
                    tourId: widget.tourId,
                    name: name,
                    kmFromStart: km,
                    highlight: highlightCtrl.text.trim(),
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('স্টপ যোগ করা যায়নি: $e'),
                      backgroundColor: Colors.redAccent,
                    ));
                  }
                }
              },
              child: const Text('যোগ করুন',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      kmCtrl.dispose();
      highlightCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final milestones = _getRouteMilestones();
    final visible = milestones.where(_matchesFilter).toList();
    final origin = _tourGroup?.originCity ?? 'রংপুর';
    final dest = _tourGroup?.destination ?? 'কক্সবাজার';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text('$origin ➔ $dest রোডম্যাপ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded,
                color: Colors.tealAccent),
            tooltip: 'নতুন চেকপয়েন্ট যোগ করুন',
            onPressed: _showAddMilestoneDialog,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'আমার লোকেশন রিফ্রেশ',
            onPressed: _fetchGps,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Overview Card
            _buildOverviewHeader(milestones),

            if (!_isDhakaOrigin)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'এই রুমের দূরত্ব ও স্টপ ঢাকা থেকে যাত্রার জন্য হিসাব করা। অন্য শহর থেকে যাত্রায় নিজের স্টপ যোগ করুন।',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                ),
              ),
            // Filter Chips
            _buildFilterTabs(milestones),

            // Milestones Timeline
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  return _buildMilestoneTile(
                      visible[index], index, visible.length);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewHeader(List<HighwayMilestone> milestones) {
    final totalKm = milestones.isNotEmpty ? milestones.last.kmFromStart : 100;
    double progress = 0.25;
    String statusSubtitle = 'যাত্রাপথ শুরু হয়েছে';
    final origin = _tourGroup?.originCity ?? 'যাত্রা স্থান';
    final dest = _tourGroup?.destination ?? 'গন্তব্য';

    if (_currentPosition != null && milestones.isNotEmpty) {
      // Progress follows the nearest stop that has coordinates. The old
      // straight-line estimate was wrong on bent roads.
      HighwayMilestone? nearest;
      var nearestMetres = double.infinity;
      for (final m in milestones) {
        if (m.lat == 0 && m.lng == 0) continue;
        final d = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          m.lat,
          m.lng,
        );
        if (d < nearestMetres) {
          nearestMetres = d;
          nearest = m;
        }
      }
      if (nearest != null && totalKm > 0) {
        progress = (nearest.kmFromStart / totalKm).clamp(0.0, 1.0);
        statusSubtitle =
            'কাছের স্টপ: ${nearest.name} (প্রায় ${(nearestMetres / 1000).toStringAsFixed(1)} কি.মি.)';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF142428),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route,
                      color: Colors.tealAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$origin ➔ $dest জাতীয় মহাসড়ক',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('~$totalKm কি.মি.',
                    style: const TextStyle(
                        color: Colors.tealAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Route Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF263D42),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$origin (০ কি.মি.)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text(statusSubtitle,
                  style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              Text('$dest ($totalKm কি.মি.)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(List<HighwayMilestone> milestones) {
    final filters = [
      'সব চেকপয়েন্ট (${milestones.length})',
      'বিরতি ও খাবার',
      'নামাজঘর',
      'ফুয়েল/পাম্প'
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, i) {
          final isSelected = _activeFilterIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filters[i]),
              selected: isSelected,
              selectedColor: Colors.tealAccent.shade700,
              backgroundColor: const Color(0xFF182B30),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                if (val) setState(() => _activeFilterIndex = i);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMilestoneTile(HighwayMilestone m, int index, int totalCount) {
    // Check filters
    if (_activeFilterIndex == 1 &&
        !m.amenities.any((a) =>
            a.contains('রেস্তোরাঁ') ||
            a.contains('নাস্তা') ||
            a.contains('খাবার') ||
            a.contains('ক্যাফে'))) {
      return const SizedBox.shrink();
    }
    if (_activeFilterIndex == 2 &&
        !m.amenities.any((a) => a.contains('নামাজ'))) {
      return const SizedBox.shrink();
    }
    if (_activeFilterIndex == 3 &&
        !m.amenities.any((a) =>
            a.contains('পাম্প') || a.contains('তেল') || a.contains('ফুয়েল'))) {
      return const SizedBox.shrink();
    }

    final isFirst = index == 0;
    final isLast = index == totalCount - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Indicator
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isLast
                        ? Colors.amber
                        : (isFirst ? Colors.green : const Color(0xFF1E3A40)),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      m.iconEmoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.teal.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Milestone Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF142428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          m.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${m.kmFromStart} কি.মি.',
                          style: const TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${m.nameEn} • সময়: ${m.estDuration}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '✨ ${m.highlight}',
                      style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.details,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  // Amenities chips & Map button
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: m.amenities.map((a) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(a,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 10)),
                            );
                          }).toList(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.map,
                            size: 18, color: Colors.tealAccent),
                        tooltip: 'ম্যাপে দেখুন',
                        onPressed: (m.lat == 0 && m.lng == 0)
                            ? null
                            : () => _openLocationOnMap(m.lat, m.lng),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
