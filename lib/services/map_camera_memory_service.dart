import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[MapCameraMemoryService] $message');
  }
}

/// Part of the "offline map tiles" gap-analysis item (#2). True offline
/// tile pre-download/caching is NOT implemented here - see
/// FarmMapWidget's class doc comment for why (google_maps_flutter has no
/// offline-regions API, and caching Google's tiles outside their own
/// offline feature violates their Terms of Service). What IS implemented
/// (this service) is the smaller, safe half of that gap: remembering
/// where on the map the user last was, so re-opening FarmMapWidget -
/// especially with a flaky/offline connection, when tiles may take a
/// while to (re)load or never load at all - centers the camera on
/// familiar ground immediately instead of re-doing a full
/// Liberia-wide-view -> zoom-to-point animation every single time.
///
/// Storage: a single shared_preferences key holding the MOST RECENT
/// camera position/zoom only (not per-farm history) - this is a "resume
/// where I was" convenience, not a navigation log, so one slot is
/// sufficient and keeps the storage footprint trivial.
class MapCameraMemoryService {
  static const String _key = 'last_map_camera_position';

  Future<void> saveLastPosition({
    required double lat,
    required double lng,
    required double zoom,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode({'lat': lat, 'lng': lng, 'zoom': zoom});
      await prefs.setString(_key, data);
    } catch (e) {
      // Best-effort only - losing this convenience data should never
      // interrupt the actual mapping flow.
      _log('Failed to save last camera position: $e');
    }
  }

  /// Returns the last remembered {lat, lng, zoom}, or null if none has
  /// been saved yet (first-ever map open on this device/install).
  Future<Map<String, double>?> getLastPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'lat': (decoded['lat'] as num).toDouble(),
        'lng': (decoded['lng'] as num).toDouble(),
        'zoom': (decoded['zoom'] as num).toDouble(),
      };
    } catch (e) {
      _log('Failed to read last camera position: $e');
      return null;
    }
  }
}
