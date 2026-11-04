/// Curated offline map regions, bounding coordinates, key waypoints, and
/// emergency assistance numbers for low-reception remote Bangladesh travel zones.
library;

class OfflineWaypoint {
  const OfflineWaypoint({
    required this.nameBn,
    required this.nameEn,
    required this.lat,
    required this.lng,
    required this.category,
  });

  final String nameBn;
  final String nameEn;
  final double lat;
  final double lng;

  /// 'viewpoint', 'camp', 'medical', 'water', 'shelter'
  final String category;
}

class OfflineEmergencyContact {
  const OfflineEmergencyContact({
    required this.titleBn,
    required this.titleEn,
    required this.phone,
  });

  final String titleBn;
  final String titleEn;
  final String phone;
}

class OfflineMapRegion {
  const OfflineMapRegion({
    required this.id,
    required this.nameBn,
    required this.nameEn,
    required this.division,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.centerLat,
    required this.centerLng,
    required this.minZoom,
    required this.maxZoom,
    required this.estimatedMb,
    required this.waypoints,
    required this.contacts,
  });

  final String id;
  final String nameBn;
  final String nameEn;
  final String division;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final double centerLat;
  final double centerLng;
  final int minZoom;
  final int maxZoom;
  final int estimatedMb;
  final List<OfflineWaypoint> waypoints;
  final List<OfflineEmergencyContact> contacts;

  /// Returns whether a GPS coordinate falls within this region's bounding box.
  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}

const List<OfflineMapRegion> kCuratedOfflineRegions = [
  OfflineMapRegion(
    id: 'sajek_valley',
    nameBn: 'সাজেক ভ্যালি ও রুইলুই',
    nameEn: 'Sajek Valley & Ruilui',
    division: 'Chattogram',
    minLat: 23.30,
    maxLat: 23.48,
    minLng: 92.20,
    maxLng: 92.35,
    centerLat: 23.3833,
    centerLng: 92.2833,
    minZoom: 10,
    maxZoom: 15,
    estimatedMb: 18,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'রুইলুই পাড়া (মূল সেন্টার)',
        nameEn: 'Ruilui Para (Main Center)',
        lat: 23.3820,
        lng: 92.2840,
        category: 'shelter',
      ),
      OfflineWaypoint(
        nameBn: 'কংলাক পাহাড় চূড়া',
        nameEn: 'Konglak Peak Viewpoint',
        lat: 23.4110,
        lng: 92.2980,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'হেলিপ্যাড ১ সূর্যাস্ত পয়েন্ট',
        nameEn: 'Helipad 1 Sunset Point',
        lat: 23.3812,
        lng: 92.2811,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'সাজেক আর্মি ক্যাম্প ও তথ্যকেন্দ্র',
        nameEn: 'Sajek Army Camp & Info Center',
        lat: 23.3845,
        lng: 92.2852,
        category: 'camp',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'সাজেক ট্যুরিস্ট পুলিশ',
        titleEn: 'Sajek Tourist Police',
        phone: '01320183277',
      ),
      OfflineEmergencyContact(
        titleBn: 'বাঘাইছড়ি থানা ও পুলিশ ক্যাম্প',
        titleEn: 'Baghaichhari Police Camp',
        phone: '01769332211',
      ),
    ],
  ),
  OfflineMapRegion(
    id: 'tanguar_haor',
    nameBn: 'টাঙ্গুয়ার হাওর ও টেকেরঘাট',
    nameEn: 'Tanguar Haor & Tekerghat',
    division: 'Sylhet',
    minLat: 25.05,
    maxLat: 25.20,
    minLng: 90.98,
    maxLng: 91.15,
    centerLat: 25.1250,
    centerLng: 91.0667,
    minZoom: 10,
    maxZoom: 15,
    estimatedMb: 14,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'নীলাদ্রি লেক (শহীদ সিরাজ লেক)',
        nameEn: 'Niladri Lake',
        lat: 25.1885,
        lng: 91.1210,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'হাওর সেন্ট্রাল ওয়াচ টাওয়ার',
        nameEn: 'Haor Central Watch Tower',
        lat: 25.1230,
        lng: 91.0650,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'বারেক টিলা ও যাদুকাটা নদী সংগম',
        nameEn: 'Barek Tila & Jadukata River',
        lat: 25.1950,
        lng: 91.2410,
        category: 'viewpoint',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'তাহিরপুর থানা',
        titleEn: 'Tahirpur Police Station',
        phone: '01320119850',
      ),
      OfflineEmergencyContact(
        titleBn: 'সুনামগঞ্জ ট্যুরিস্ট পুলিশ',
        titleEn: 'Sunamganj Tourist Police',
        phone: '01320183280',
      ),
    ],
  ),
  OfflineMapRegion(
    id: 'bandarban_highlands',
    nameBn: 'বান্দরবান হাইল্যান্ড ও কেওক্রাডং',
    nameEn: 'Bandarban Highlands & Keokradong',
    division: 'Chattogram',
    minLat: 21.85,
    maxLat: 22.05,
    minLng: 92.45,
    maxLng: 92.62,
    centerLat: 21.9500,
    centerLng: 92.5333,
    minZoom: 10,
    maxZoom: 15,
    estimatedMb: 26,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'বগা লেক আর্মি ক্যাম্প ও কটেজ',
        nameEn: 'Boga Lake Camp & Cottages',
        lat: 21.9772,
        lng: 92.5204,
        category: 'shelter',
      ),
      OfflineWaypoint(
        nameBn: 'কেওক্রাডং পর্বতচূড়া',
        nameEn: 'Keokradong Summit',
        lat: 21.9500,
        lng: 92.5333,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'দার্জিলিং পাড়া রেস্ট স্টপ',
        nameEn: 'Darjeeling Para Rest Stop',
        lat: 21.9610,
        lng: 92.5270,
        category: 'shelter',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'রুমা আর্মি ক্যাম্প গাইড সেল',
        titleEn: 'Ruma Army Camp Guide Cell',
        phone: '01869871122',
      ),
      OfflineEmergencyContact(
        titleBn: 'রুমা থানা কন্ট্রোল রুম',
        titleEn: 'Ruma Thana Control Room',
        phone: '01320108500',
      ),
    ],
  ),
  OfflineMapRegion(
    id: 'sundarbans_riverways',
    nameBn: 'সুন্দরবন নদীপথ ও কটকা',
    nameEn: 'Sundarbans Riverways & Kotka',
    division: 'Khulna',
    minLat: 21.75,
    maxLat: 22.00,
    minLng: 89.65,
    maxLng: 89.90,
    centerLat: 21.8500,
    centerLng: 89.7800,
    minZoom: 9,
    maxZoom: 14,
    estimatedMb: 22,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'কটকা ফরেস্ট স্টেশন ও ওয়াচ টাওয়ার',
        nameEn: 'Kotka Forest Station & Tower',
        lat: 21.8540,
        lng: 89.7820,
        category: 'camp',
      ),
      OfflineWaypoint(
        nameBn: 'জামতোলা সি বিচ ট্রেইল',
        nameEn: 'Jamtola Sea Beach Trail',
        lat: 21.8410,
        lng: 89.7910,
        category: 'viewpoint',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'কোস্ট গার্ড পশ্চিম জোন (মংলা)',
        titleEn: 'Coast Guard West (Mongla)',
        phone: '01769440999',
      ),
      OfflineEmergencyContact(
        titleBn: 'বন বিভাগ সুন্দরবন পূর্ব রেঞ্জ',
        titleEn: 'Sundarbans Forest Department',
        phone: '01712001122',
      ),
    ],
  ),
  OfflineMapRegion(
    id: 'saint_martins',
    nameBn: 'সেন্টমার্টিন দ্বীপ ও ছেঁড়া দ্বীপ',
    nameEn: "Saint Martin's Island & Chera Dwip",
    division: 'Chattogram',
    minLat: 20.58,
    maxLat: 20.65,
    minLng: 92.30,
    maxLng: 92.35,
    centerLat: 20.6233,
    centerLng: 92.3233,
    minZoom: 11,
    maxZoom: 16,
    estimatedMb: 8,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'সেন্টমার্টিন মূল জেটিঘাট',
        nameEn: 'Main Jetty Ghat',
        lat: 20.6320,
        lng: 92.3210,
        category: 'shelter',
      ),
      OfflineWaypoint(
        nameBn: 'ছেঁড়া দ্বীপ প্রবাল পয়েন্ট',
        nameEn: 'Chera Dwip Coral Point',
        lat: 20.5890,
        lng: 92.3380,
        category: 'viewpoint',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'সেন্টমার্টিন পুলিশ ফাঁড়ি',
        titleEn: "Saint Martin's Police Outpost",
        phone: '01320108855',
      ),
      OfflineEmergencyContact(
        titleBn: 'টেকনাফ কোস্ট গার্ড স্টেশন',
        titleEn: 'Teknaf Coast Guard Station',
        phone: '01769440777',
      ),
    ],
  ),
  OfflineMapRegion(
    id: 'sreemangal_lawachara',
    nameBn: 'শ্রীমঙ্গল চা বাগান ও লাউয়াছড়া',
    nameEn: 'Sreemangal Tea Gardens & Lawachara',
    division: 'Sylhet',
    minLat: 24.25,
    maxLat: 24.38,
    minLng: 91.70,
    maxLng: 91.88,
    centerLat: 24.3065,
    centerLng: 91.7296,
    minZoom: 10,
    maxZoom: 15,
    estimatedMb: 16,
    waypoints: [
      OfflineWaypoint(
        nameBn: 'লাউয়াছড়া জাতীয় উদ্যান এন্ট্রি গেট',
        nameEn: 'Lawachara National Park Gate',
        lat: 24.3325,
        lng: 91.7850,
        category: 'viewpoint',
      ),
      OfflineWaypoint(
        nameBn: 'বাইক্কা বিল পাখি অভয়ারণ্য',
        nameEn: 'Baikka Beel Bird Sanctuary',
        lat: 24.3512,
        lng: 91.6840,
        category: 'viewpoint',
      ),
    ],
    contacts: [
      OfflineEmergencyContact(
        titleBn: 'শ্রীমঙ্গল থানা',
        titleEn: 'Sreemangal Police Station',
        phone: '01320119300',
      ),
      OfflineEmergencyContact(
        titleBn: 'শ্রীমঙ্গল উপজেলা স্বাস্থ্য কমপ্লেক্স',
        titleEn: 'Sreemangal Health Complex',
        phone: '01712334455',
      ),
    ],
  ),
];
