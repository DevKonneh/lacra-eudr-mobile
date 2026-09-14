import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/pending_sync_item.dart';
import '../models/farmer_registration_model.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Queues farmer registrations locally when the device has no connectivity
/// (or the live submission to the backend fails for a network reason), then
/// retries them against the backend's offline-sync endpoints
/// (POST /farmer/offline-sync, POST /farm/offline-sync) once connectivity
/// is restored, or when the user taps "Sync Now".
///
/// Storage: shared_preferences, as a single JSON-encoded list under a
/// per-logged-in-user key. This is a lightweight local queue - no server
/// round trip is required to enqueue an item, so registration can never be
/// blocked by network state.
///
/// IMPORTANT: Keys are scoped per logged-in user (by user id), not shared
/// device-wide. Multiple inspectors commonly share the same physical
/// device/app install, and shared_preferences data survives logout/login
/// (AuthService.logout() only clears the auth token) - without per-user
/// scoping, Inspector B logging in after Inspector A would see Inspector
/// A's still-unsynced field registrations, which looks like "the app is
/// showing another user's previous work". A one-time migration folds any
/// pre-existing legacy (unscoped) queue into whichever user is currently
/// logged in the first time this runs after the update, so no unsynced
/// field data is silently lost.
class OfflineSyncService {
  static const String _legacyKey = 'pending_farmer_sync_queue';

  /// After this many failed multipart (with-photos) sync attempts, a
  /// queued item permanently switches to the JSON-only fallback endpoint
  /// (see syncPendingItems()) so the farmer/farm record is saved even
  /// though the photos can't be delivered on this connection - protects
  /// against a registration being lost forever because of oversized
  /// attachments on a weak rural connection.
  static const int _kMaxMultipartRetriesBeforeFallback = 4;

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  Future<String?> _currentUserId() async {
    final user = await _authService.getUser();
    return user?.id;
  }

  String _keyFor(String? userId) =>
      userId != null ? 'pending_farmer_sync_queue_$userId' : _legacyKey;

  /// One-time migration: if this user has no per-user pending-sync data yet
  /// but legacy (unscoped, pre-fix) data exists on the device, adopt it
  /// into this user's bucket rather than leaving it invisible/orphaned,
  /// then remove the legacy key so it isn't picked up again by a different
  /// user.
  Future<void> _migrateLegacyIfNeeded(
    SharedPreferences prefs,
    String key,
  ) async {
    if (key == _legacyKey) return; // no logged-in user to migrate into
    if (prefs.containsKey(key)) return; // already has its own scoped data
    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw == null) return;
    await prefs.setString(key, legacyRaw);
    await prefs.remove(_legacyKey);
    _log('Migrated legacy device-wide pending-sync queue into user-scoped storage');
  }

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[OfflineSync] $message');
    }
  }

  /// Checks actual network connectivity (not just that the device *has* an
  /// interface - connectivity_plus reports interface state, so a definitive
  /// "can I reach the backend" check still happens per-request via the real
  /// HTTP call in [syncPendingItems]).
  Future<bool> hasConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none) && result.isNotEmpty;
  }

  /// Builds the backend-shaped {farmer, farms} payload from the mobile
  /// FarmerRegistrationModel + captured boundary, matching exactly what
  /// FarmerController.offlineSync() / FarmController.offlineSync() expect.
  Map<String, dynamic> _buildFarmerPayload(FarmerRegistrationModel data) {
    return {
      'firstName': data.fullName.split(' ').isNotEmpty
          ? data.fullName.split(' ').first
          : data.fullName,
      'lastName': data.fullName.split(' ').length > 1
          ? data.fullName.split(' ').sublist(1).join(' ')
          : '',
      'phoneNumber': data.phone,
      'email': data.email,
      'nationalId': data.nationalId,
      'idType': data.idType,
      'idTypeOther': data.idTypeOther,
      'gender': data.gender,
      'address': data.directions,
      'community': data.community,
      'district': data.district,
      'region': data.county,
      'consent': data.consent,
      'cooperativeName': data.cooperativeName,
      'cooperativeId': data.cooperativeId,
      'enumeratorId': data.enumeratorId,
      'enumeratorName': data.inspectorName,
    };
  }

  Map<String, dynamic> _buildFarmPayload(FarmerRegistrationModel data) {
    Map<String, dynamic>? location;
    if (data.boundaryJson != null && data.boundaryJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(data.boundaryJson!);
        location = (decoded is Map && decoded['geometry'] != null)
            ? Map<String, dynamic>.from(decoded['geometry'] as Map)
            : Map<String, dynamic>.from(decoded as Map);
      } catch (_) {
        location = null;
      }
    }
    return {
      'name': data.farmName,
      'cropType': data.crop,
      if (location != null) 'location': location,
      if (data.areaHa != null) 'totalAreaHa': data.areaHa,
      if (data.numberOfTrees != null) 'numberOfTrees': data.numberOfTrees,
      if (data.yearsInCultivation != null)
        'yearsInCultivation': data.yearsInCultivation,
      if (data.harvestSeason != null) 'harvestSeason': data.harvestSeason,
      if (data.averageYield != null) 'averageYield': data.averageYield,
      if (data.buyers != null) 'buyers': data.buyers,
      'useChemicals': data.useChemicals,
      'extensionServices': data.extensionServices,
      if (data.farmAddress != null) 'farmAddress': data.farmAddress,
    };
  }

  /// Adds a farmer registration to the local pending-sync queue. Call this
  /// when a live submission fails due to a network error (or when offline
  /// is detected before even attempting the live call).
  ///
  /// Stores the FULL registration snapshot (via [FarmerRegistrationModel.
  /// toFullJson]), including local file paths for photos/signature and any
  /// boundary evidence, so [syncPendingItems] can later replay the exact
  /// same multipart submission a live registration would have used -
  /// otherwise photos/signature captured while offline would be silently
  /// dropped on sync (the legacy [_buildFarmerPayload]/[_buildFarmPayload]
  /// JSON-only shape below is kept only as a fallback for the backend's
  /// JSON-only offline-sync endpoint, in case a multipart resubmission
  /// ever fails and a text-only save is better than losing the record).
  Future<void> enqueue(FarmerRegistrationModel data) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await _migrateLegacyIfNeeded(prefs, key);
    final items = await _loadItems(prefs, key);

    final farmPayload = _buildFarmPayload(data);
    final hasUsableFarm =
        (farmPayload['name'] as String).trim().isNotEmpty &&
        (farmPayload['cropType'] as String).trim().isNotEmpty &&
        farmPayload['location'] != null;

    final item = PendingSyncItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      farmer: _buildFarmerPayload(data),
      farms: hasUsableFarm ? [farmPayload] : [],
      registration: data.toFullJson(),
      createdAt: DateTime.now(),
    );

    items.add(item);
    await _saveItems(prefs, key, items);
    _log(
      'Enqueued pending registration for "${item.displayName}" '
      '(queue size: ${items.length})',
    );

    // Best-effort: let the backend know this registration exists somewhere
    // on this device, even though it hasn't synced yet. This is a tiny
    // text-only summary (no photos/geometry) so it has a real chance of
    // getting through even on the same weak connection that caused this
    // item to be queued in the first place. A failure here must never
    // affect the local queue - it only means admin visibility lags behind
    // slightly, which is strictly better than the previous behavior of
    // no visibility at all.
    _reportShadowRecord(item);
  }

  /// Sends (or updates) the backend's lightweight "offline submission"
  /// shadow record for [item], for admin/inspector visibility into data
  /// that's queued locally but not yet fully synced. Never throws - any
  /// failure (no connectivity, timeout, server error) is swallowed after
  /// logging, since this is purely a visibility nicety and must not block
  /// or interfere with the actual local-queue-based sync flow.
  Future<void> _reportShadowRecord(PendingSyncItem item) async {
    try {
      final token = await _authService.getToken();
      final farm = item.farms.isNotEmpty ? item.farms.first : null;
      await _apiService.reportOfflineSubmission(
        clientId: item.id,
        displayName: item.displayName,
        phoneNumber: item.farmer['phoneNumber'] as String?,
        community: item.farmer['community'] as String?,
        district: item.farmer['district'] as String?,
        region: item.farmer['region'] as String?,
        farmName: farm?['name'] as String?,
        cropType: farm?['cropType'] as String?,
        retryCount: item.retryCount,
        lastError: item.lastError,
        capturedAt: item.createdAt,
        authToken: token,
      );
    } catch (e) {
      _log('Could not report shadow record for "${item.displayName}": $e');
    }
  }

  /// Best-effort tells the backend an item has finished syncing (or been
  /// discarded locally), so its shadow record stops showing up as "still
  /// offline" in admin visibility. Never throws.
  Future<void> _resolveShadowRecord(
    String clientId, {
    String? syncedFarmerId,
  }) async {
    try {
      final token = await _authService.getToken();
      await _apiService.resolveOfflineSubmission(
        clientId: clientId,
        syncedFarmerId: syncedFarmerId,
        authToken: token,
      );
    } catch (e) {
      _log('Could not resolve shadow record for "$clientId": $e');
    }
  }

  /// Public wrapper so callers outside this service (e.g. the farmer
  /// registry wizard's "discard draft"/live-submission-success paths) can
  /// resolve a shadow record without needing access to private internals.
  Future<void> resolveShadowRecord(String clientId, {String? syncedFarmerId}) =>
      _resolveShadowRecord(clientId, syncedFarmerId: syncedFarmerId);

  Future<List<PendingSyncItem>> getPendingItems() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await _migrateLegacyIfNeeded(prefs, key);
    return _loadItems(prefs, key);
  }

  Future<int> pendingCount() async {
    final items = await getPendingItems();
    return items.length;
  }

  Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    final items = await _loadItems(prefs, key);
    items.removeWhere((i) => i.id == id);
    await _saveItems(prefs, key, items);
    // Discarded locally by the inspector - stop showing it as "still
    // offline" in admin visibility.
    unawaited(_resolveShadowRecord(id));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await prefs.remove(key);
  }

  Future<List<PendingSyncItem>> _loadItems(
    SharedPreferences prefs,
    String key,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PendingSyncItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('Failed to decode pending sync queue, resetting it: $e');
      return [];
    }
  }

  Future<void> _saveItems(
    SharedPreferences prefs,
    String key,
    List<PendingSyncItem> items,
  ) async {
    final encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    await prefs.setString(key, encoded);
  }

  /// Attempts to sync every pending item to the backend. Items that
  /// succeed are removed from the queue; items that fail keep their
  /// place in the queue with an incremented retry count and the last
  /// error message recorded, so the UI can show why they're still
  /// pending.
  ///
  /// Items that carry a full [PendingSyncItem.registration] snapshot are
  /// synced via [_syncViaMultipart], replaying the exact multipart
  /// [ApiService.registerFarmer] call so any locally-captured photos/
  /// signature upload correctly. Older items enqueued before this
  /// snapshot existed (no [PendingSyncItem.registration]) fall back to
  /// the JSON-only [ApiService.syncFarmerOffline] - the farmer/farm record
  /// itself is still saved, just without photos, so nothing is lost.
  Future<OfflineSyncResult> syncPendingItems() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await _migrateLegacyIfNeeded(prefs, key);
    final items = await _loadItems(prefs, key);

    if (items.isEmpty) {
      return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
    }

    final token = await _authService.getToken();
    int synced = 0;
    int failed = 0;
    final List<PendingSyncItem> stillPending = [];

    for (final item in items) {
      try {
        String? syncedFarmerId;
        bool usedFallback = false;
        if (item.registration != null && !item.forceJsonFallback) {
          final response = await _syncViaMultipart(item, token);
          final responseData = response['data'];
          // The backend returns the full saved Farmer object as `data`
          // (see FarmerController.create/offlineSync) - its `id` is the
          // real Farmer primary key, not a separate `farmerId` field
          // (that field holds the human-readable "LACRA-XXXX" label).
          syncedFarmerId = responseData is Map
              ? responseData['id']?.toString()
              : null;
        } else {
          // Either a legacy item (enqueued before full snapshots existed,
          // no photos were ever captured for it), OR a full-snapshot item
          // that has now been explicitly flagged to fall back to the
          // JSON-only path (see forceJsonFallback below) after repeatedly
          // failing to upload as multipart - almost always because the
          // combined photo payload is too large for the field connection.
          // Either way, this saves the CORE farmer/farm record (name,
          // phone, location, boundary) even when photos can't be
          // delivered, rather than leaving the data stuck in this queue
          // indefinitely.
          usedFallback = item.registration != null;
          final response = await _apiService.syncFarmerOffline(
            farmer: item.farmer,
            farms: item.farms,
            authToken: token,
          );
          final responseData = response['data'];
          syncedFarmerId = responseData is Map
              ? (responseData['id'])?.toString()
              : null;
        }
        synced++;
        _log(
          usedFallback
              ? 'Synced "${item.displayName}" via JSON-only fallback '
                  '(photos NOT uploaded - core record saved)'
              : 'Synced "${item.displayName}" successfully',
        );
        // Now that the real Farmer record exists, the shadow record no
        // longer needs to show up as "still offline" in admin visibility.
        unawaited(
          _resolveShadowRecord(item.id, syncedFarmerId: syncedFarmerId),
        );
      } catch (e) {
        failed++;
        item.retryCount += 1;
        item.lastError = e.toString().replaceAll('Exception: ', '');
        // Safety net: a full-snapshot (multipart) item that has failed
        // repeatedly is very likely failing because of upload SIZE (photos
        // + signature + documents), not because the server is genuinely
        // unreachable for plain JSON too - the small text-only
        // _reportShadowRecord() calls made from this same device keep
        // succeeding throughout these retries (see enqueue()/the catch
        // block below), which is exactly this pattern. Once a full-
        // snapshot item has failed [_kMaxMultipartRetriesBeforeFallback]
        // times, permanently switch it to JSON-only sync on the NEXT
        // attempt so the farmer/farm record itself doesn't stay stuck (and
        // therefore at risk of being lost) forever - only the photos are
        // sacrificed, and that is disclosed to the inspector via
        // lastError below so they know to re-attach photos later if
        // needed.
        if (item.registration != null &&
            !item.forceJsonFallback &&
            item.retryCount >= _kMaxMultipartRetriesBeforeFallback) {
          item.forceJsonFallback = true;
          item.lastError =
              'Photos/documents are too large to upload on this connection '
              'after $_kMaxMultipartRetriesBeforeFallback attempts. The '
              'next "Sync Now" will save this farmer WITHOUT photos so the '
              'record is not lost - you can re-attach photos from the '
              'farmer\'s profile later once on a better connection.';
          _log(
            'Switching "${item.displayName}" to JSON-only fallback after '
            '${item.retryCount} failed multipart attempts',
          );
        }
        stillPending.add(item);
        _log('Failed to sync "${item.displayName}": ${item.lastError}');
        // Keep admin visibility up to date with the latest retry count/
        // error, so it's clear this item has actually been attempted (and
        // failed) rather than sitting untouched.
        unawaited(_reportShadowRecord(item));
      }
    }

    await _saveItems(prefs, key, stillPending);

    return OfflineSyncResult(
      synced: synced,
      failed: failed,
      remaining: stillPending.length,
    );
  }

  /// Rebuilds a [FarmerRegistrationModel] from [item.registration] and
  /// resubmits it through the same multipart [ApiService.registerFarmer]
  /// call a live/online submission would use, so any farmer photo,
  /// national ID photo, farm selfie, signature, and farm photos captured
  /// while offline are uploaded to Cloudinary exactly as they would be for
  /// an online registration. If EUDR boundary-evidence points were
  /// captured, they're attached via a best-effort follow-up call once the
  /// farm id is known (a failure there does not roll back the already-
  /// saved farmer/farm - it's logged and surfaced via [PendingSyncItem.
  /// lastError] would only apply to the outer registerFarmer call, so this
  /// inner failure is just logged, matching the online submission's own
  /// behavior in farmer_registry_screen.dart).
  Future<Map<String, dynamic>> _syncViaMultipart(
    PendingSyncItem item,
    String? token,
  ) async {
    final data = FarmerRegistrationModel.fromFullJson(item.registration!);
    final response = await _apiService.registerFarmer(
      farmerData: data,
      authToken: token,
    );

    if (data.boundaryEvidence != null && data.boundaryEvidence!.isNotEmpty) {
      try {
        final responseData = response['data'];
        final farmId = responseData is Map
            ? responseData['farmId'] as String?
            : null;
        if (farmId != null) {
          await _apiService.addBoundaryEvidence(
            farmId: farmId,
            points: data.boundaryEvidence!,
            authToken: token,
          );
        } else {
          _log(
            'No farmId returned when syncing "${item.displayName}" - '
            'boundary evidence not attached.',
          );
        }
      } catch (evidenceError) {
        _log(
          'Farmer "${item.displayName}" synced, but boundary evidence '
          'failed to attach: $evidenceError',
        );
      }
    }

    return response;
  }
}
