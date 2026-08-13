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
    };
  }

  /// Adds a farmer registration to the local pending-sync queue. Call this
  /// when a live submission fails due to a network error (or when offline
  /// is detected before even attempting the live call).
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
      createdAt: DateTime.now(),
    );

    items.add(item);
    await _saveItems(prefs, items);
    _log('Enqueued pending registration for "${item.displayName}" '
        '(queue size: ${items.length})');
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
        // Sync the farmer first; the backend creates the Farmer record and
        // any farms passed inline in the same call.
        await _apiService.syncFarmerOffline(
          farmer: item.farmer,
          farms: item.farms,
          authToken: token,
        );
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
}
