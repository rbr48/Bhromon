// Pure domain models for Tour Group Engine

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

class TourMember {
  final String tourId;
  final String email;
  final String displayName;
  final String? photoUrl;
  final TourRole role;
  final TourMemberStatus status;
  final DateTime joinedAt;

  const TourMember({
    required this.tourId,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'email': email.toLowerCase().trim(),
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.toValue(),
      'status': status.toValue(),
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  factory TourMember.fromMap(Map<String, dynamic> map) {
    return TourMember(
      tourId: map['tourId'] as String? ?? '',
      email: (map['email'] as String? ?? '').toLowerCase().trim(),
      displayName: map['displayName'] as String? ?? 'Explorer',
      photoUrl: map['photoUrl'] as String?,
      role: TourRole.fromString(map['role'] as String?),
      status: TourMemberStatus.fromString(map['status'] as String?),
      joinedAt: map['joinedAt'] != null
          ? DateTime.tryParse(map['joinedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
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
}

class TourGroup {
  final String id;
  final String name;
  final String description;
  final String destination;
  final String ownerEmail;
  final String inviteCode;
  final DateTime startDate;
  final DateTime endDate;
  final TourModules modules;
  final DateTime createdAt;

  const TourGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.destination = "Cox's Bazar",
    required this.ownerEmail,
    required this.inviteCode,
    required this.startDate,
    required this.endDate,
    this.modules = const TourModules(),
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'destination': destination,
      'ownerEmail': ownerEmail.toLowerCase().trim(),
      'inviteCode': inviteCode,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'modules': modules.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'schemaVersion': 2,
    };
  }

  factory TourGroup.fromMap(String id, Map<String, dynamic> map) {
    return TourGroup(
      id: id,
      name: map['name'] as String? ?? 'Family Tour',
      description: map['description'] as String? ?? '',
      destination: map['destination'] as String? ?? "Cox's Bazar",
      ownerEmail: (map['ownerEmail'] as String? ?? '').toLowerCase().trim(),
      inviteCode: map['inviteCode'] as String? ?? '',
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endDate: map['endDate'] != null
          ? DateTime.tryParse(map['endDate'].toString()) ??
              DateTime.now().add(const Duration(days: 4))
          : DateTime.now().add(const Duration(days: 4)),
      modules: TourModules.fromMap(map['modules'] as Map<String, dynamic>?),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
