/// Read-only models for displaying farmers (and their farms) that were
/// already submitted to the backend. These mirror the TypeORM entities
/// `Farmer` and `Farm` (see backend src/entities/Farmer.ts, Farm.ts) as
/// returned by GET /api/farmers and GET /api/farmers/:id.
///
/// All fields are nullable/defensive on purpose: the backend columns are
/// mostly `nullable: true`, and we never want a single missing/odd field
/// to crash the whole list screen for an inspector in the field.
library;

/// Mirrors the backend's `Farm.geometryStatus` enum
/// (src/entities/Farm.ts) - the cached outcome of the last GPS
/// polygon/area validation run (GeometryValidationService), computed
/// server-side on every farm create/sync and never recalculated on the
/// mobile client. "Missing" is the enum default for farms that have never
/// been validated (e.g. very old records created before this feature
/// existed), so it is treated the same as "unknown" here rather than as a
/// failure.
enum FarmGeometryStatus { valid, needsReview, invalid, missing, unknown }

FarmGeometryStatus _parseGeometryStatus(dynamic raw) {
  switch (raw?.toString()) {
    case 'Valid':
      return FarmGeometryStatus.valid;
    case 'Needs Review':
      return FarmGeometryStatus.needsReview;
    case 'Invalid':
      return FarmGeometryStatus.invalid;
    case 'Missing':
      return FarmGeometryStatus.missing;
    default:
      return FarmGeometryStatus.unknown;
  }
}

extension FarmGeometryStatusLabel on FarmGeometryStatus {
  /// Matches the exact string the backend enum uses (see
  /// AppTheme.statusColor/statusBgColor), so this can be passed straight
  /// into a [StatusBadge].
  String get label {
    switch (this) {
      case FarmGeometryStatus.valid:
        return 'Valid';
      case FarmGeometryStatus.needsReview:
        return 'Needs Review';
      case FarmGeometryStatus.invalid:
        return 'Invalid';
      case FarmGeometryStatus.missing:
      case FarmGeometryStatus.unknown:
        return 'Not Yet Validated';
    }
  }
}

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
  final Map<String, dynamic>? location;

  // --- GPS polygon / farm-area geometry validation (see
  // backend FarmGeometryHelper.validateAndAnnotateFarm) - computed on the
  // server, cached on the Farm row, and surfaced here READ-ONLY so an
  // enumerator can see at a glance whether a boundary they drew needs a
  // second look, without having to go find the admin panel.
  final FarmGeometryStatus geometryStatus;
  final double? calculatedAreaHa;
  final double? areaDifferenceHa;
  final double? areaDifferencePercent;
  final double? gpsAccuracyM;
  final int coordinateCount;
  final bool overlapsExistingFarm;
  final List<String> geometryWarnings;
  final List<String> geometryErrors;

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
    this.location,
    this.geometryStatus = FarmGeometryStatus.unknown,
    this.calculatedAreaHa,
    this.areaDifferenceHa,
    this.areaDifferencePercent,
    this.gpsAccuracyM,
    this.coordinateCount = 0,
    this.overlapsExistingFarm = false,
    this.geometryWarnings = const [],
    this.geometryErrors = const [],
  });

  /// True when this farm's boundary is worth flagging to the enumerator:
  /// either the server marked it Needs Review/Invalid, or it overlaps
  /// another farm's polygon. "Missing"/"unknown" are NOT flagged here -
  /// those just mean "never validated", not "something is wrong".
  bool get needsAttention =>
      geometryStatus == FarmGeometryStatus.needsReview ||
      geometryStatus == FarmGeometryStatus.invalid ||
      overlapsExistingFarm;

  factory FarmRecord.fromJson(Map<String, dynamic> json) {
    final details = json['geometryValidationDetails'];
    final warnings = details is Map && details['warnings'] is List
        ? List<String>.from(
            (details['warnings'] as List).map((e) => e.toString()),
          )
        : const <String>[];
    final errors = details is Map && details['errors'] is List
        ? List<String>.from(
            (details['errors'] as List).map((e) => e.toString()),
          )
        : const <String>[];

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
      location: json['location'] is Map
          ? Map<String, dynamic>.from(json['location'] as Map)
          : null,
      geometryStatus: _parseGeometryStatus(json['geometryStatus']),
      calculatedAreaHa: json['calculatedAreaHa'] is num
          ? (json['calculatedAreaHa'] as num).toDouble()
          : null,
      areaDifferenceHa: json['areaDifferenceHa'] is num
          ? (json['areaDifferenceHa'] as num).toDouble()
          : null,
      areaDifferencePercent: json['areaDifferencePercent'] is num
          ? (json['areaDifferencePercent'] as num).toDouble()
          : null,
      gpsAccuracyM: json['gpsAccuracyM'] is num
          ? (json['gpsAccuracyM'] as num).toDouble()
          : null,
      coordinateCount: json['coordinateCount'] is num
          ? (json['coordinateCount'] as num).toInt()
          : 0,
      overlapsExistingFarm: json['overlapsExistingFarm'] is bool
          ? json['overlapsExistingFarm'] as bool
          : false,
      geometryWarnings: warnings,
      geometryErrors: errors,
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
