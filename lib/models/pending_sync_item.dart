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
/// Lifecycle status for a queued registration (task spec section 12).
///
/// A record only ever enters this queue once it has already passed full
/// validation in the wizard (see FarmerRegistryScreen._submitForm), so
/// [readyToSync] is the initial state for everything created via
/// [OfflineSyncService.enqueue] today - [draft] is reserved for future use
/// if partial/incomplete records are ever allowed into this same queue.
enum SyncStatus {
  draft,
  readyToSync,
  syncing,
  synced,
  syncFailed,
}

SyncStatus _syncStatusFromString(String? raw) {
  switch (raw) {
    case 'draft':
      return SyncStatus.draft;
    case 'syncing':
      return SyncStatus.syncing;
    case 'synced':
      return SyncStatus.synced;
    case 'syncFailed':
      return SyncStatus.syncFailed;
    case 'readyToSync':
      return SyncStatus.readyToSync;
    default:
      return SyncStatus.readyToSync;
  }
}

String _syncStatusToString(SyncStatus status) => status.name;

class PendingSyncItem {
  /// Stable local identifier, generated once when the record is enqueued
  /// and NEVER changed afterwards - including after a successful sync
  /// (task spec section 9: "local ID must remain unchanged when synced").
  /// Also doubles as the client-side dedup key: see
  /// OfflineSyncService/_buildFarmerPayload, which sends this as
  /// `clientRecordId` so the backend can reject a duplicate create if the
  /// same record is ever submitted twice (task spec section 13).
  final String id;
  final Map<String, dynamic> farmer;
  final List<Map<String, dynamic>> farms;
  final Map<String, dynamic>? registration;
  final DateTime createdAt;
  int retryCount;
  String? lastError;

  /// Set by OfflineSyncService once a full-snapshot (multipart, with
  /// photos) item has failed to sync too many times - from then on, sync
  /// attempts use the lightweight JSON-only endpoint instead (no photos),
  /// so the core farmer/farm record can still be saved rather than staying
  /// stuck in this queue indefinitely. See
  /// OfflineSyncService._kMaxMultipartRetriesBeforeFallback.
  bool forceJsonFallback;

  /// Current lifecycle status - see [SyncStatus]. Drives the badge/section
  /// shown in PendingSyncScreen's dashboard (task spec sections 12/16).
  SyncStatus status;

  /// Whether this record's checkbox is currently ticked in the Pending
  /// Sync screen. Purely UI/session state - defaults to false so that
  /// syncing is always an explicit, deliberate choice by the enumerator
  /// (task spec sections 10/11: never auto-select/auto-sync).
  bool selected;

  PendingSyncItem({
    required this.id,
    required this.farmer,
    required this.farms,
    this.registration,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.forceJsonFallback = false,
    this.status = SyncStatus.readyToSync,
    this.selected = false,
  });

  /// Best-effort display name for showing in the pending-sync list UI.
  String get displayName {
    final first = (farmer['firstName'] ?? '').toString().trim();
    final last = (farmer['lastName'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unnamed farmer' : full;
  }

  /// Human-friendly record code shown in the UI (e.g. "FARM-2026-000001"
  /// from task spec section 9's example). Purely cosmetic - the actual
  /// stable/dedup identifier is always [id] itself.
  String get displayId {
    final year = createdAt.year.toString();
    final suffix = (id.hashCode.abs() % 1000000).toString().padLeft(6, '0');
    return 'FARM-$year-$suffix';
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
      forceJsonFallback: json['forceJsonFallback'] as bool? ?? false,
      status: _syncStatusFromString(json['status'] as String?),
      // selected is intentionally NOT persisted - always starts unchecked
      // on load (e.g. after an app restart) so a stale selection can never
      // silently cause an unintended sync.
      selected: false,
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
      if (forceJsonFallback) 'forceJsonFallback': forceJsonFallback,
      'status': _syncStatusToString(status),
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
