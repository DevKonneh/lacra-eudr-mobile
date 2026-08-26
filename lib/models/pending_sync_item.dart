/// Represents a farmer (+ optional farm) registration that was captured
/// while the device had no network connectivity. It is persisted locally
/// (see OfflineSyncService) and later synced to the backend.
///
/// [registration] carries the FULL registration snapshot (including local
/// file paths for photos/signature and boundary evidence) via
/// FarmerRegistrationModel.toFullJson() - when present, syncing replays the
/// exact same multipart ApiService.registerFarmer() call used for a live
/// submission, so photos/signature upload correctly instead of being
/// silently dropped.
///
/// [farmer]/[farms] are kept as a fallback JSON-only shape (no files) for
/// backward compatibility with items already sitting in a device's queue
/// from before [registration] existed - those are synced via the older
/// JSON-only POST /farmers/offline-sync endpoint (no photos, but at least
/// the farmer/farm record itself isn't lost).
class PendingSyncItem {
  final String id;
  final Map<String, dynamic> farmer;
  final List<Map<String, dynamic>> farms;
  final Map<String, dynamic>? registration;
  final DateTime createdAt;
  int retryCount;
  String? lastError;

  PendingSyncItem({
    required this.id,
    required this.farmer,
    required this.farms,
    this.registration,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
  });

  /// Best-effort display name for showing in the pending-sync list UI.
  String get displayName {
    final first = (farmer['firstName'] ?? '').toString().trim();
    final last = (farmer['lastName'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unnamed farmer' : full;
  }

  factory PendingSyncItem.fromJson(Map<String, dynamic> json) {
    return PendingSyncItem(
      id: json['id'] as String,
      farmer: Map<String, dynamic>.from(json['farmer'] as Map),
      farms: (json['farms'] as List<dynamic>? ?? [])
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList(),
      registration: json['registration'] != null
          ? Map<String, dynamic>.from(json['registration'] as Map)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'farmer': farmer,
      'farms': farms,
      if (registration != null) 'registration': registration,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      if (lastError != null) 'lastError': lastError,
    };
  }
}

/// Summary returned after attempting to flush the offline sync queue.
class OfflineSyncResult {
  final int synced;
  final int failed;
  final int remaining;

  const OfflineSyncResult({
    required this.synced,
    required this.failed,
    required this.remaining,
  });
}
