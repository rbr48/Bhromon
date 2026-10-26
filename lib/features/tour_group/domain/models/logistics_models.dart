// Domain models for Bus Seats & Hotel Rooms

import 'date_codec.dart';

/// Used by copyWith to tell "not passed" apart from an explicit null.
const Object _keep = Object();

class BusSeat {
  final String seatNumber; // e.g. "A1", "A2", "B1", "B2", ... "I4"
  final String? assignedMemberEmail;
  final String? assignedMemberName;
  final bool isWindow;

  /// The vehicle this seat belongs to, or null for the tour's original coach
  /// (stored in `bus_seats`).
  final String? vehicleId;

  /// Which of the member's family seats this is: 0 for the member, 1 and up
  /// for the people travelling with them.
  final int familySlot;

  const BusSeat({
    required this.seatNumber,
    this.assignedMemberEmail,
    this.assignedMemberName,
    this.isWindow = false,
    this.vehicleId,
    this.familySlot = 0,
  });

  bool get isOccupied =>
      assignedMemberEmail != null && assignedMemberEmail!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'seatNumber': seatNumber,
      'assignedMemberEmail': assignedMemberEmail,
      'assignedMemberName': assignedMemberName,
      'isWindow': isWindow,
      if (vehicleId != null) 'vehicleId': vehicleId,
      'familySlot': familySlot,
    };
  }

  factory BusSeat.fromMap(Map<String, dynamic> map) {
    return BusSeat(
      seatNumber: map['seatNumber'] as String? ?? '',
      assignedMemberEmail: map['assignedMemberEmail'] as String?,
      assignedMemberName: map['assignedMemberName'] as String?,
      isWindow: map['isWindow'] as bool? ?? false,
      vehicleId: map['vehicleId'] as String?,
      familySlot: (map['familySlot'] as num?)?.toInt() ?? 0,
    );
  }

  /// Arguments left out keep their value. Pass null explicitly to clear them.
  BusSeat copyWith({
    Object? assignedMemberEmail = _keep,
    Object? assignedMemberName = _keep,
  }) {
    return BusSeat(
      seatNumber: seatNumber,
      assignedMemberEmail: identical(assignedMemberEmail, _keep)
          ? this.assignedMemberEmail
          : assignedMemberEmail as String?,
      assignedMemberName: identical(assignedMemberName, _keep)
          ? this.assignedMemberName
          : assignedMemberName as String?,
      isWindow: isWindow,
      vehicleId: vehicleId,
      familySlot: familySlot,
    );
  }
}

/// The bed types a room may have.
const List<String> kBedTypes = ['single', 'double', 'twin', 'king', 'family'];

class HotelRoom {
  final String id;
  final String roomNumber; // e.g. "301", "302"
  final String title; // e.g. "Deluxe Sea View Suite"
  final int capacity; // persons per room
  final int floor;
  final bool isAc;
  final bool hasSeaView;
  final bool hasBalcony;

  /// The hotel or resort, for tours that stay in more than one. Empty when
  /// the tour has one hotel.
  final String hotelName;

  /// One of [kBedTypes], or empty when not set.
  final String bedType;

  /// Guest emails and names. The two lists are kept the same length; the name
  /// at index i belongs to the email at index i. Use [addGuest]/[removeGuest]
  /// so they stay aligned.
  final List<String> assignedMemberEmails;
  final List<String> assignedMemberNames;

  const HotelRoom({
    required this.id,
    required this.roomNumber,
    required this.title,
    this.capacity = 2,
    this.floor = 1,
    this.isAc = true,
    this.hasSeaView = false,
    this.hasBalcony = false,
    this.hotelName = '',
    this.bedType = '',
    this.assignedMemberEmails = const [],
    this.assignedMemberNames = const [],
  });

  bool get isFull => assignedMemberEmails.length >= capacity;

  /// People in the room, counting each guest's family: a member travelling
  /// with three others takes four places. Guests missing from [familySizes]
  /// count as one.
  int peopleIn(Map<String, int> familySizes) => assignedMemberEmails.fold(
      0, (n, e) => n + (familySizes[e] ?? 1).clamp(1, 20));

  /// Whether a family of [size] still fits, counting families already in.
  bool fitsFamily(int size, Map<String, int> familySizes) =>
      !isFull && peopleIn(familySizes) + size <= capacity;
  int get availableSlots => capacity - assignedMemberEmails.length;

  bool hasGuest(String email) =>
      assignedMemberEmails.contains(normalizeEmail(email));

  /// Returns a room with [email] added. Throws [StateError] when the room is
  /// full or the guest is already in it.
  HotelRoom addGuest(String email, String name) {
    final normalized = normalizeEmail(email);
    if (hasGuest(normalized)) {
      throw StateError('এই সদস্য ইতিমধ্যে এই রুমে আছেন।');
    }
    if (isFull) {
      throw StateError('রুমটি পূর্ণ, নতুন সদস্য যোগ করা যাবে না।');
    }
    return _with(
      emails: [...assignedMemberEmails, normalized],
      names: [..._alignedNames(), name],
    );
  }

  /// Returns a room with [email] removed. Unknown emails leave it unchanged.
  HotelRoom removeGuest(String email) {
    final normalized = normalizeEmail(email);
    final index = assignedMemberEmails.indexOf(normalized);
    if (index < 0) return this;
    final names = _alignedNames()..removeAt(index);
    final emails = [...assignedMemberEmails]..removeAt(index);
    return _with(emails: emails, names: names);
  }

  HotelRoom copyWith({
    String? roomNumber,
    String? title,
    int? capacity,
    int? floor,
    bool? isAc,
    bool? hasSeaView,
    bool? hasBalcony,
    String? hotelName,
    String? bedType,
  }) {
    return HotelRoom(
      id: id,
      roomNumber: roomNumber ?? this.roomNumber,
      title: title ?? this.title,
      capacity: capacity ?? this.capacity,
      floor: floor ?? this.floor,
      isAc: isAc ?? this.isAc,
      hasSeaView: hasSeaView ?? this.hasSeaView,
      hasBalcony: hasBalcony ?? this.hasBalcony,
      hotelName: hotelName ?? this.hotelName,
      bedType: bedType ?? this.bedType,
      assignedMemberEmails: assignedMemberEmails,
      assignedMemberNames: assignedMemberNames,
    );
  }

  List<String> _alignedNames() => List.generate(assignedMemberEmails.length,
      (i) => i < assignedMemberNames.length ? assignedMemberNames[i] : '');

  HotelRoom _with({required List<String> emails, required List<String> names}) {
    return HotelRoom(
      id: id,
      roomNumber: roomNumber,
      title: title,
      capacity: capacity,
      floor: floor,
      isAc: isAc,
      hasSeaView: hasSeaView,
      hasBalcony: hasBalcony,
      hotelName: hotelName,
      bedType: bedType,
      assignedMemberEmails: emails,
      assignedMemberNames: names,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomNumber': roomNumber,
      'title': title,
      'capacity': capacity,
      'floor': floor,
      'isAc': isAc,
      'hasSeaView': hasSeaView,
      'hasBalcony': hasBalcony,
      'hotelName': hotelName,
      'bedType': bedType,
      'assignedMemberEmails': assignedMemberEmails,
      'assignedMemberNames': _alignedNames(),
    };
  }

  factory HotelRoom.fromMap(String id, Map<String, dynamic> map) {
    final emails = (map['assignedMemberEmails'] as List<dynamic>?)
            ?.map((e) => normalizeEmail(e.toString()))
            .toList() ??
        <String>[];
    final names = (map['assignedMemberNames'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final room = HotelRoom(
      id: id,
      roomNumber: map['roomNumber'] as String? ?? '',
      title: map['title'] as String? ?? 'Room',
      capacity: (map['capacity'] as num?)?.toInt() ?? 2,
      floor: (map['floor'] as num?)?.toInt() ?? 1,
      isAc: map['isAc'] as bool? ?? true,
      hasSeaView: map['hasSeaView'] as bool? ?? false,
      hasBalcony: map['hasBalcony'] as bool? ?? false,
      hotelName: map['hotelName'] as String? ?? '',
      bedType:
          kBedTypes.contains(map['bedType']) ? map['bedType'] as String : '',
      assignedMemberEmails: emails,
      assignedMemberNames: names,
    );
    return room._with(emails: emails, names: room._alignedNames());
  }
}
