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
/// Storage: shared_preferences, as a single JSON-encoded list under
/// [_storageKey]. This is a lightweight local queue - no server round trip
/// is required to enqueue an item, so registration can never be blocked by
/// network state.
class OfflineSyncService {
  static const String _storageKey = 'pending_farmer_sync_queue';

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

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
    final items = await _loadItems(prefs);

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
    await _saveItems(prefs, items);
    _log(
      'Enqueued pending registration for "${item.displayName}" '
      '(queue size: ${items.length})',
    );
  }

  Future<List<PendingSyncItem>> getPendingItems() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadItems(prefs);
  }

  Future<int> pendingCount() async {
    final items = await getPendingItems();
    return items.length;
  }

  Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _loadItems(prefs);
    items.removeWhere((i) => i.id == id);
    await _saveItems(prefs, items);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<List<PendingSyncItem>> _loadItems(SharedPreferences prefs) async {
    final raw = prefs.getString(_storageKey);
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
    List<PendingSyncItem> items,
  ) async {
    final encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
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
    final items = await _loadItems(prefs);

    if (items.isEmpty) {
      return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
    }

    final token = await _authService.getToken();
    int synced = 0;
    int failed = 0;
    final List<PendingSyncItem> stillPending = [];

    for (final item in items) {
      try {
        if (item.registration != null) {
          await _syncViaMultipart(item, token);
        } else {
          // Legacy item (enqueued before full snapshots existed) - sync
          // the farmer/farm record via the JSON-only endpoint. No photos
          // were ever captured for this item, since the old enqueue()
          // never stored file paths in the first place.
          await _apiService.syncFarmerOffline(
            farmer: item.farmer,
            farms: item.farms,
            authToken: token,
          );
        }
        synced++;
        _log('Synced "${item.displayName}" successfully');
      } catch (e) {
        failed++;
        item.retryCount += 1;
        item.lastError = e.toString().replaceAll('Exception: ', '');
        stillPending.add(item);
        _log('Failed to sync "${item.displayName}": ${item.lastError}');
      }
    }

    await _saveItems(prefs, stillPending);

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
  Future<void> _syncViaMultipart(PendingSyncItem item, String? token) async {
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
  }
}
