/// Backend-visible "shadow record" of a farmer registration that an
/// inspector's device captured while offline (or whose live submission
/// failed due to a network error), but which has NOT yet fully synced to
/// the real Farmer/Farm tables.
///
/// This mirrors the backend `OfflineSubmission` entity (see
/// src/entities/OfflineSubmission.ts in the backend repo) and is what gives
/// admins/other inspectors visibility into field data that exists on a
/// device somewhere but hasn't reached the server yet - previously this was
/// completely invisible until the device with connectivity finally synced.
class OfflineSubmissionRecord {
  final String id;
  final String clientId;
  final String inspectorId;
  final String? inspectorName;
  final String? displayName;
  final String? phoneNumber;
  final String? community;
  final String? district;
  final String? region;
  final String? farmName;
  final String? cropType;
  final String status; // PENDING | SYNCED | FAILED
  final int retryCount;
  final String? lastError;
  final DateTime? capturedAt;
  final DateTime reportedAt;
  final DateTime updatedAt;

  const OfflineSubmissionRecord({
    required this.id,
    required this.clientId,
    required this.inspectorId,
    this.inspectorName,
    this.displayName,
    this.phoneNumber,
    this.community,
    this.district,
    this.region,
    this.farmName,
    this.cropType,
    required this.status,
    required this.retryCount,
    this.lastError,
    this.capturedAt,
    required this.reportedAt,
    required this.updatedAt,
  });

  String get resolvedDisplayName =>
      (displayName == null || displayName!.trim().isEmpty)
      ? 'Unnamed farmer'
      : displayName!.trim();

  String get locationSummary {
    final parts = [
      community,
      district,
    ].where((s) => (s ?? '').trim().isNotEmpty).toList();
    return parts.join(', ');
  }

  factory OfflineSubmissionRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return OfflineSubmissionRecord(
      id: json['id']?.toString() ?? '',
      clientId: json['clientId']?.toString() ?? '',
      inspectorId: json['inspectorId']?.toString() ?? '',
      inspectorName: json['inspectorName'] as String?,
      displayName: json['displayName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      community: json['community'] as String?,
      district: json['district'] as String?,
      region: json['region'] as String?,
      farmName: json['farmName'] as String?,
      cropType: json['cropType'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      capturedAt: parseDate(json['capturedAt']),
      reportedAt: parseDate(json['reportedAt']) ?? DateTime.now(),
      updatedAt: parseDate(json['updatedAt']) ?? DateTime.now(),
    );
  }
}
