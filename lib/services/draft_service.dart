import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/draft_item.dart';
import 'auth_service.dart';

/// Persists in-progress farmer registrations that the inspector chose to
/// "Save as Draft" rather than submit. Storage: shared_preferences, as a
/// single JSON-encoded list under a per-logged-in-user key - the same
/// lightweight local-only approach used by OfflineSyncService, since
/// drafts are never sent to the backend until the inspector resumes and
/// taps "Submit".
///
/// IMPORTANT: Keys are scoped per logged-in user (by user id), not shared
/// device-wide. Multiple inspectors commonly share the same physical
/// device/app install, and shared_preferences data survives logout/login
/// (AuthService.logout() only clears the auth token) - without per-user
/// scoping, Inspector B logging in after Inspector A would see Inspector
/// A's saved drafts, which looks like "the app is showing another user's
/// previous work". A one-time migration folds any pre-existing legacy
/// (unscoped) drafts into whichever user is currently logged in the first
/// time this runs after the update, so no in-progress work is silently
/// lost.
class DraftService {
  static const String _legacyKey = 'farmer_registration_drafts';
  final AuthService _authService = AuthService();

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[DraftService] $message');
    }
  }

  Future<String?> _currentUserId() async {
    final user = await _authService.getUser();
    return user?.id;
  }

  String _keyFor(String? userId) =>
      userId != null ? 'farmer_registration_drafts_$userId' : _legacyKey;

  /// One-time migration: if this user has no per-user draft data yet but
  /// legacy (unscoped, pre-fix) data exists on the device, adopt it into
  /// this user's bucket rather than leaving it invisible/orphaned, then
  /// remove the legacy key so it isn't picked up again by a different user.
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
    _log('Migrated legacy device-wide drafts into user-scoped storage');
  }

  /// Saves a new draft or updates an existing one (matched by [id], if
  /// provided). Returns the id of the saved draft, so a freshly-created
  /// draft can be tracked for subsequent auto-updates within the same
  /// editing session.
  Future<String> saveDraft({
    String? id,
    required Map<String, dynamic> formData,
    Map<String, dynamic>? boundaryJson,
    List<Map<String, dynamic>>? boundaryEvidence,
    required int currentStep,
    required List<bool> stepCompleted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await _migrateLegacyIfNeeded(prefs, key);
    final drafts = await _loadDrafts(prefs, key);

    final now = DateTime.now();
    final existingIndex = id == null
        ? -1
        : drafts.indexWhere((d) => d.id == id);

    final draft = DraftItem(
      id: id ?? now.microsecondsSinceEpoch.toString(),
      formData: Map<String, dynamic>.from(formData),
      boundaryJson: boundaryJson,
      boundaryEvidence: boundaryEvidence,
      currentStep: currentStep,
      stepCompleted: List<bool>.from(stepCompleted),
      createdAt: existingIndex == -1 ? now : drafts[existingIndex].createdAt,
      updatedAt: now,
    );

    if (existingIndex == -1) {
      drafts.add(draft);
    } else {
      drafts[existingIndex] = draft;
    }

    await _saveDrafts(prefs, key, drafts);
    _log(
      'Saved draft for "${draft.displayName}" '
      '(total drafts: ${drafts.length})',
    );
    return draft.id;
  }

  Future<List<DraftItem>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    await _migrateLegacyIfNeeded(prefs, key);
    final drafts = await _loadDrafts(prefs, key);
    // Most recently updated first, so the draft an inspector was just
    // working on is always at the top of the list.
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  Future<int> draftCount() async {
    final drafts = await getDrafts();
    return drafts.length;
  }

  Future<void> deleteDraft(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(await _currentUserId());
    final drafts = await _loadDrafts(prefs, key);
    drafts.removeWhere((d) => d.id == id);
    await _saveDrafts(prefs, key, drafts);
  }

  Future<List<DraftItem>> _loadDrafts(
    SharedPreferences prefs,
    String key,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => DraftItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('Failed to decode drafts, resetting: $e');
      return [];
    }
  }

  Future<void> _saveDrafts(
    SharedPreferences prefs,
    String key,
    List<DraftItem> drafts,
  ) async {
    final encoded = jsonEncode(drafts.map((d) => d.toJson()).toList());
    await prefs.setString(key, encoded);
  }
}
