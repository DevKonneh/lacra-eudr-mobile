/// Read-only models for displaying farmers (and their farms) that were
/// already submitted to the backend. These mirror the TypeORM entities
/// `Farmer` and `Farm` (see backend src/entities/Farmer.ts, Farm.ts) as
/// returned by GET /api/farmers and GET /api/farmers/:id.
///
/// All fields are nullable/defensive on purpose: the backend columns are
/// mostly `nullable: true`, and we never want a single missing/odd field
/// to crash the whole list screen for an inspector in the field.
library;

class FarmRecord {
  final String id;
  final String name;
  final String? cropType;
  final String? riskLevel;
  final double? totalAreaHa;
  final String? ownershipType;
  final String? farmRegistrationStatus;
  final String? farmNotes;
  final List<String> farmPhotos;
  final DateTime? createdAt;

  FarmRecord({
    required this.id,
    required this.name,
    this.cropType,
    this.riskLevel,
    this.totalAreaHa,
    this.ownershipType,
    this.farmRegistrationStatus,
    this.farmNotes,
    this.farmPhotos = const [],
    this.createdAt,
  });

  factory FarmRecord.fromJson(Map<String, dynamic> json) {
    return FarmRecord(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Unnamed Farm').toString(),
      cropType: json['cropType']?.toString(),
      riskLevel: json['riskLevel']?.toString(),
      totalAreaHa: json['totalAreaHa'] is num
          ? (json['totalAreaHa'] as num).toDouble()
          : double.tryParse('${json['totalAreaHa']}'),
      ownershipType: json['ownershipType']?.toString(),
      farmRegistrationStatus: json['farmRegistrationStatus']?.toString(),
      farmNotes: json['farmNotes']?.toString(),
      farmPhotos: json['farmPhotos'] is List
          ? List<String>.from(
              (json['farmPhotos'] as List).map((e) => e.toString()),
            )
          : const [],
      createdAt: DateTime.tryParse('${json['createdAt']}'),
    );
  }
}

class FarmerRecord {
  final String id;
  final String? farmerId;
  final String firstName;
  final String lastName;
  final String? email;
  final String phoneNumber;
  final String? gender;
  final String? nationality;
  final String? community;
  final String? district;
  final String? region;
  final String? address;
  final String? enumeratorName;
  final String identityStatus;
  final bool isActive;
  final bool consent;
  final String? profilePhoto;
  final String? qrCode;
  final DateTime? createdAt;
  final List<FarmRecord> farms;

  FarmerRecord({
    required this.id,
    this.farmerId,
    required this.firstName,
    required this.lastName,
    this.email,
    required this.phoneNumber,
    this.gender,
    this.nationality,
    this.community,
    this.district,
    this.region,
    this.address,
    this.enumeratorName,
    this.identityStatus = 'Unverified',
    this.isActive = true,
    this.consent = false,
    this.profilePhoto,
    this.qrCode,
    this.createdAt,
    this.farms = const [],
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Unknown Farmer' : name;
  }

  factory FarmerRecord.fromJson(Map<String, dynamic> json) {
    return FarmerRecord(
      id: (json['id'] ?? '').toString(),
      farmerId: json['farmerId']?.toString(),
      firstName: (json['firstName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      email: json['email']?.toString(),
      phoneNumber: (json['phoneNumber'] ?? '').toString(),
      gender: json['gender']?.toString(),
      nationality: json['nationality']?.toString(),
      community: json['community']?.toString(),
      district: json['district']?.toString(),
      region: json['region']?.toString(),
      address: json['address']?.toString(),
      enumeratorName: json['enumeratorName']?.toString(),
      identityStatus: (json['identityStatus'] ?? 'Unverified').toString(),
      isActive: json['isActive'] is bool ? json['isActive'] as bool : true,
      consent: json['consent'] is bool ? json['consent'] as bool : false,
      profilePhoto: json['profilePhoto']?.toString(),
      qrCode: json['qrCode']?.toString(),
      createdAt: DateTime.tryParse('${json['createdAt']}'),
      farms: json['farms'] is List
          ? (json['farms'] as List)
                .whereType<Map<String, dynamic>>()
                .map(FarmRecord.fromJson)
                .toList()
          : const [],
    );
  }
}
