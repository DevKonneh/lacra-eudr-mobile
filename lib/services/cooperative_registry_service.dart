import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/cda_cooperatives.dart';
import 'api_service.dart';

/// Loads the real CDA (Cooperative Development Agency) registry from the
/// backend (`GET /api/cooperatives`) and keeps a local offline cache, so
/// FarmerPersonalInfoStep's cooperative picker works both online and
/// offline - consistent with the app's offline-first ground rule and the
/// same shared_preferences-based caching approach already used by
/// DraftService/OfflineSyncService.
///
/// This is device-wide (not per-user) data: the CDA registry is public
/// reference data, identical for every inspector, so there is no need for
/// the per-user key scoping DraftService uses for private draft data.
class CooperativeRegistryService {
  static const String _cacheKey = 'cda_cooperative_registry_cache_v1';

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[CooperativeRegistryService] $message');
    }
  }

  /// Fetches the latest registry from the backend, updates the in-memory
  /// `CdaCooperatives.entries` and the offline cache, and returns the list.
  /// On any failure (no network, timeout, backend error) falls back to
  /// whatever is cached on-device, and if there's no cache either, leaves
  /// `CdaCooperatives.entries` as the tiny built-in offline seed it already
  /// started with.
  ///
  /// Safe to call multiple times (e.g. every time the bottom sheet opens) -
  /// cheap no-op re-fetch if already loaded this session, unless
  /// [forceRefresh] is true.
  static bool _loadedThisSession = false;

  static Future<List<CdaCooperative>> load({bool forceRefresh = false}) async {
    if (_loadedThisSession && !forceRefresh) {
      return CdaCooperatives.entries;
    }

    final prefs = await SharedPreferences.getInstance();

    try {
      final fetched = await ApiService().getCooperatives();
      if (fetched.isNotEmpty) {
        CdaCooperatives.entries = List.unmodifiable(fetched);
        _loadedThisSession = true;
        await _saveCache(prefs, fetched);
        _log('Loaded ${fetched.length} cooperatives from backend');
        return CdaCooperatives.entries;
      }
      // Backend reachable but returned an empty list (e.g. not seeded yet
      // on this environment) - fall through to cache instead of wiping
      // out whatever we already had.
      _log('Backend returned 0 cooperatives, trying cache instead');
    } catch (e) {
      _log('Backend fetch failed ($e), trying cache instead');
    }

    final cached = await _loadCache(prefs);
    if (cached != null && cached.isNotEmpty) {
      CdaCooperatives.entries = List.unmodifiable(cached);
      _loadedThisSession = true;
      _log('Loaded ${cached.length} cooperatives from offline cache');
    }
    return CdaCooperatives.entries;
  }

  static Future<void> _saveCache(
    SharedPreferences prefs,
    List<CdaCooperative> coops,
  ) async {
    final raw = jsonEncode(coops.map((c) => c.toJson()).toList());
    await prefs.setString(_cacheKey, raw);
  }

  static Future<List<CdaCooperative>?> _loadCache(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CdaCooperative.fromJson)
          .toList();
    } catch (e) {
      _log('Failed to parse cached registry: $e');
      return null;
    }
  }
}
