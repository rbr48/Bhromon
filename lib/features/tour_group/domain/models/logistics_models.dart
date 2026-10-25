// Domain models for Bus Seats & Hotel Rooms

class BusSeat {
  final String seatNumber; // e.g. "A1", "A2", "B1", "B2", ... "J4"
  final String? assignedMemberEmail;
  final String? assignedMemberName;
  final bool isWindow;

  const BusSeat({
    required this.seatNumber,
    this.assignedMemberEmail,
    this.assignedMemberName,
    this.isWindow = false,
  });

  bool get isOccupied => assignedMemberEmail != null && assignedMemberEmail!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'seatNumber': seatNumber,
      'assignedMemberEmail': assignedMemberEmail,
      'assignedMemberName': assignedMemberName,
      'isWindow': isWindow,
    };
  }

  factory BusSeat.fromMap(Map<String, dynamic> map) {
    return BusSeat(
      seatNumber: map['seatNumber'] as String? ?? '',
      assignedMemberEmail: map['assignedMemberEmail'] as String?,
      assignedMemberName: map['assignedMemberName'] as String?,
      isWindow: map['isWindow'] as bool? ?? false,
    );
  }

  BusSeat copyWith({
    String? assignedMemberEmail,
    String? assignedMemberName,
  }) {
    return BusSeat(
      seatNumber: seatNumber,
      assignedMemberEmail: assignedMemberEmail,
      assignedMemberName: assignedMemberName,
      isWindow: isWindow,
    );
  }
}

class HotelRoom {
  final String id;
  final String roomNumber; // e.g. "301", "302"
  final String title; // e.g. "Deluxe Sea View Suite"
  final int capacity; // e.g. 2, 3, 4 persons
  final int floor;
  final bool isAc;
  final bool hasSeaView;
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
    this.assignedMemberEmails = const [],
    this.assignedMemberNames = const [],
  });

  bool get isFull => assignedMemberEmails.length >= capacity;
  int get availableSlots => capacity - assignedMemberEmails.length;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomNumber': roomNumber,
      'title': title,
      'capacity': capacity,
      'floor': floor,
      'isAc': isAc,
      'hasSeaView': hasSeaView,
      'assignedMemberEmails': assignedMemberEmails,
      'assignedMemberNames': assignedMemberNames,
    };
  }

  factory HotelRoom.fromMap(String id, Map<String, dynamic> map) {
    return HotelRoom(
      id: id,
      roomNumber: map['roomNumber'] as String? ?? '',
      title: map['title'] as String? ?? 'Room',
      capacity: (map['capacity'] as num?)?.toInt() ?? 2,
      floor: (map['floor'] as num?)?.toInt() ?? 1,
      isAc: map['isAc'] as bool? ?? true,
      hasSeaView: map['hasSeaView'] as bool? ?? false,
      assignedMemberEmails: (map['assignedMemberEmails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      assignedMemberNames: (map['assignedMemberNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
