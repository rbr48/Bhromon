import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class TourLandmark {
  final String id;
  final String name;
  final String subtitle;
  final double lat;
  final double lng;
  final IconData icon;
  final Color color;

  const TourLandmark({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.lat,
    required this.lng,
    required this.icon,
    required this.color,
  });
}

class FamilySafetyHubScreen extends StatefulWidget {
  final String tourId;

  const FamilySafetyHubScreen({super.key, required this.tourId});

  @override
  State<FamilySafetyHubScreen> createState() => _FamilySafetyHubScreenState();
}

class _FamilySafetyHubScreenState extends State<FamilySafetyHubScreen>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isSirenActive = false;
  late AnimationController _sirenAnimController;

  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;

  List<TourLandmark> get _landmarks {
    final dest = _tourGroup?.destination.toLowerCase() ?? 'cox';
    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return const [
        TourLandmark(
          id: 'sajek_resort',
          name: 'সাজেক কটেজ ও রিসোর্ট জোন',
          subtitle: 'প্রধান কটেজ ও থাকার রুম',
          lat: 23.3828,
          lng: 92.2938,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'sajek_vehicle',
          name: 'সাজেক চাঁদের গাড়ি পার্কিং স্ট্যান্ড',
          subtitle: 'ট্যুর গ্রুপ পরিবহন পয়েন্ট',
          lat: 23.3840,
          lng: 92.2945,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'sajek_helipad',
          name: 'সাজেক হ্যালিপ্যাড ও সানসেট পয়েন্ট',
          subtitle: 'ফ্যামিলি আড্ডা ও মিলনমেলা পয়েন্ট',
          lat: 23.3815,
          lng: 92.2930,
          icon: Icons.wb_cloudy_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'konglak_peak',
          name: 'কংলাক পাহাড় চূড়া ও লুসাই পাড়া',
          subtitle: 'ট্যুর ট্র্যাকিং ও মেঘলোক ভিউ',
          lat: 23.3980,
          lng: 92.3010,
          icon: Icons.landscape_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else if (dest.contains('sylhet') || dest.contains('সিলেট')) {
      return const [
        TourLandmark(
          id: 'syl_hotel',
          name: 'সিলেট প্রধান হোটেল ও রিসোর্ট',
          subtitle: 'প্রধান হোটেল ও থাকার রুম',
          lat: 24.8949,
          lng: 91.8687,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'syl_bus',
          name: 'ট্যুর বাস ও মাইক্রোবাস পার্কিং',
          subtitle: 'প্রধান পরিবহন পয়েন্ট',
          lat: 24.8960,
          lng: 91.8700,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'syl_ratargul',
          name: 'রাতারগুল সোয়াম্প ফরেস্ট ঘাট',
          subtitle: 'জলজ বন ও নৌকা ভ্রমণ স্পট',
          lat: 25.0050,
          lng: 91.9300,
          icon: Icons.water_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'syl_sada',
          name: 'ভোলাগঞ্জ সাদা পাথর জিরো পয়েন্ট',
          subtitle: 'স্বচ্ছ জল ও পাথুরে নদী পয়েন্ট',
          lat: 25.1634,
          lng: 92.0189,
          icon: Icons.diamond_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else if (dest.contains('bandarban') || dest.contains('বান্দরবান')) {
      return const [
        TourLandmark(
          id: 'ban_hotel',
          name: 'বান্দরবান প্রধান হোটেল ও রিসোর্ট',
          subtitle: 'প্রধান হোটেল ও থাকার রুম',
          lat: 22.1953,
          lng: 92.2184,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'ban_bus',
          name: 'চাঁদের গাড়ি স্ট্যান্ড ও বাস পার্কিং',
          subtitle: 'ট্যুর পাহাড়ি পরিবহন পয়েন্ট',
          lat: 22.1970,
          lng: 92.2190,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'ban_nilachal',
          name: 'নীলাচল ভিউপয়েন্ট ও ঝুলন্ত ব্রিজ',
          subtitle: 'সূর্যাস্ত ও মেঘ দর্শন পয়েন্ট',
          lat: 22.1800,
          lng: 92.2050,
          icon: Icons.wb_sunny_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'ban_nilgiri',
          name: 'নীলগিরি হিলটপ রিসোর্ট চূড়া',
          subtitle: 'পাহাড় চূড়া ও মেঘের সমারোহ',
          lat: 21.9189,
          lng: 92.3364,
          icon: Icons.landscape_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else {
      return [
        TourLandmark(
          id: 'hotel_sea_moon',
          name: '${_tourGroup?.destination ?? "কক্সবাজার"} প্রধান হোটেল / রিসোর্ট',
          subtitle: 'প্রধান হোটেল ও থাকার রুম',
          lat: 21.4326,
          lng: 91.9774,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'evergreen_bus',
          name: '${_tourGroup?.originCity ?? "রংপুর"} ➔ ${_tourGroup?.destination ?? "কক্সবাজার"} বাস পার্কিং',
          subtitle: 'প্রধান বাস ও পরিবহন পয়েন্ট',
          lat: 21.4385,
          lng: 91.9740,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'sugandha_beach',
          name: '${_tourGroup?.destination ?? "কক্সবাজার"} প্রধান মিলনমেলা পয়েন্ট',
          subtitle: 'ফ্যামিলি আড্ডা ও মিলনমেলা পয়েন্ট',
          lat: 21.4298,
          lng: 91.9752,
          icon: Icons.place_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'laboni_beach',
          name: '${_tourGroup?.destination ?? "কক্সবাজার"} দর্শনীয় প্রধান স্পট',
          subtitle: 'দর্শনীয় স্পট ও ফটো পয়েন্ট',
          lat: 21.4390,
          lng: 91.9712,
          icon: Icons.camera_alt_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    }
  }

  ({String title, String number, String display}) _getLocalHospitalContact() {
    final dest = _tourGroup?.destination.toLowerCase() ?? '';
    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return (
        title: 'খাগড়াছড়ি সদর হাসপাতাল ও ইমার্জেন্সি',
        number: '01730324790',
        display: '01730-324790',
      );
    } else if (dest.contains('sylhet') || dest.contains('সিলেট')) {
      return (
        title: 'সিলেট এম এ জি ওসমানী মেডিকেল হাসপাতাল',
        number: '01730324795',
        display: '01730-324795',
      );
    } else if (dest.contains('bandarban') || dest.contains('বান্দরবান')) {
      return (
        title: 'বান্দরবান সদর হাসপাতাল ও ইমার্জেন্সি',
        number: '01730324799',
        display: '01730-324799',
      );
    } else if (dest.contains('cox') || dest.contains('কক্সবাজার')) {
      return (
        title: 'কক্সবাজার সদর হাসপাতাল ইমার্জেন্সি',
        number: '01730324785',
        display: '01730-324785',
      );
    } else {
      return (
        title: 'জাতীয় স্বাস্থ্য হেল্পলাইন ও অ্যাম্বুলেন্স',
        number: '16263',
        display: '16263 (২৪ ঘণ্টা ফ্রি)',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGroup();
    _sirenAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _initGps();
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) setState(() => _tourGroup = g);
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _sirenAnimController.dispose();
    super.dispose();
  }

  Future<void> _initGps() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _currentPosition = pos);

        _positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          if (mounted) setState(() => _currentPosition = pos);
        });
      }
    } catch (_) {
      // Fallback gracefully if GPS permission denied or disabled
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openMapNavigation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaLambda = (lon2 - lon1) * math.pi / 180;

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B1E),
      appBar: AppBar(
        title: const Text('Family Safety Hub (নিরাপত্তা ও জরুরি সেবা)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // SOS Emergency Beacon
            _buildSosBeacon(),

            const SizedBox(height: 16),

            // Emergency Contacts
            _buildEmergencyContactsSection(),

            const SizedBox(height: 20),

            // Live Landmark Direction Cards
            const Text(
              'গুরুত্বপূর্ণ ট্যুর পয়েন্ট ও কম্পাস ডিরেকশন',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),

            ..._landmarks.map((l) => _buildLandmarkCard(l)),

            const SizedBox(height: 20),

            // Safety Guidelines
            _buildSafetyGuidelines(),
          ],
        ),
      ),
    );
  }

  Widget _buildSosBeacon() {
    return AnimatedBuilder(
      animation: _sirenAnimController,
      builder: (context, child) {
        final alertColor = _isSirenActive
            ? Color.lerp(Colors.red.shade900, Colors.redAccent, _sirenAnimController.value)!
            : const Color(0xFF1F2E33);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: alertColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isSirenActive ? Colors.redAccent : Colors.white12,
              width: _isSirenActive ? 2 : 1,
            ),
            boxShadow: _isSirenActive
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 4,
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSirenActive ? Colors.white : Colors.red.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isSirenActive ? Icons.notifications_active : Icons.shield,
                      color: _isSirenActive ? Colors.red : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSirenActive ? 'জরুরি সাইরেন সক্রিয়!' : 'ফ্যামিলি ইমার্জেন্সি এসওএস',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSirenActive
                              ? 'কাছের মানুষদের দৃষ্টি আকর্ষণ করতে সাইরেন বাজছে।'
                              : 'বিপদে পড়লে বা দলছুট হলে তাৎক্ষণিক সাইরেন ও হটলাইন ব্যবহার করুন।',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(_isSirenActive ? Icons.volume_off : Icons.volume_up),
                  label: Text(
                    _isSirenActive ? 'সাইরেন বন্ধ করুন' : 'জরুরি সাইরেন চালু করুন',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSirenActive ? Colors.white : Colors.redAccent.shade700,
                    foregroundColor: _isSirenActive ? Colors.red.shade900 : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() {
                      _isSirenActive = !_isSirenActive;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmergencyContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'এক-ট্যাপে জরুরি কল (EMERGENCY HOTLINES)',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildDialCard(
                title: 'ট্যুরিস্ট পুলিশ',
                number: '01320163599',
                displayNumber: '01320-163599',
                icon: Icons.local_police,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDialCard(
                title: 'জাতীয় জরুরি সেবা',
                number: '999',
                displayNumber: '999 (ফ্রি)',
                icon: Icons.emergency,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final h = _getLocalHospitalContact();
            return _buildFullWidthDialCard(
              title: h.title,
              number: h.number,
              displayNumber: h.display,
              icon: Icons.local_hospital,
              color: Colors.teal,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDialCard({
    required String title,
    required String number,
    required String displayNumber,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _callNumber(number),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF142428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(displayNumber, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthDialCard({
    required String title,
    required String number,
    required String displayNumber,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _callNumber(number),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF142428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(displayNumber, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.phone_in_talk, color: Colors.greenAccent, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLandmarkCard(TourLandmark landmark) {
    int? distanceMeters;
    double? bearing;

    if (_currentPosition != null) {
      distanceMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        landmark.lat,
        landmark.lng,
      ).round();

      bearing = _calculateBearing(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        landmark.lat,
        landmark.lng,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: landmark.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: landmark.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(landmark.icon, color: landmark.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  landmark.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  landmark.subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                if (distanceMeters != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.near_me, size: 12, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      Text(
                        distanceMeters > 1000
                            ? '${(distanceMeters / 1000).toStringAsFixed(1)} কি.মি. দূরে'
                            : '$distanceMeters মিটার দূরে',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      if (bearing != null) ...[
                        const SizedBox(width: 8),
                        Transform.rotate(
                          angle: (bearing * math.pi / 180),
                          child: const Icon(Icons.arrow_upward, size: 12, color: Colors.amberAccent),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions, color: Colors.tealAccent),
            tooltip: 'গুগল ম্যাপে ডিরেকশন',
            onPressed: () => _openMapNavigation(landmark.lat, landmark.lng),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyGuidelines() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF102024),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text(
                'পরিবারের সুরক্ষা ও সমুদ্র সতর্কতা নির্দেশিকা',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• লাল পতাকা ওড়ালে কোনোভাবেই সমুদ্রে নামবেন না।\n'
            '• ভাটার সময় সমুদ্রের টান (Rip Current) অত্যন্ত তীব্র থাকে, কোমর পানির বেশি নামবেন না।\n'
            '• হোটেল সি মুন ও বাস পার্কিং পয়েন্টের কম্পাস ডিরেকশন সেভ রাখুন যাতে ভিড়ের মধ্যে পথ হারিয়ে না যায়।\n'
            '• যেকোনো অনাকাঙ্ক্ষিত পরিস্থিতিতে সরাসরি ট্যুরিস্ট পুলিশ (01320-163599) বা ৯৯৯ নম্বরে ফোন দিন।',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
