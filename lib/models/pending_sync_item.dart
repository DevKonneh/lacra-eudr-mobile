/// Represents a farmer (+ optional farm) registration that was captured
/// while the device had no network connectivity. It is persisted locally
/// (see OfflineSyncService) and later synced to the backend via
/// POST /farmer/offline-sync once connectivity is restored.
class PendingSyncItem {
  final String id;
  final Map<String, dynamic> farmer;
  final List<Map<String, dynamic>> farms;
  final DateTime createdAt;
  int retryCount;
  String? lastError;

  PendingSyncItem({
    required this.id,
    required this.farmer,
    required this.farms,
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
