import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/draft_item.dart';

/// Persists in-progress farmer registrations that the inspector chose to
/// "Save as Draft" rather than submit. Storage: shared_preferences, as a
/// single JSON-encoded list under [_storageKey] - the same lightweight
/// local-only approach used by OfflineSyncService, since drafts are never
/// sent to the backend until the inspector resumes and taps "Submit".
class DraftService {
  static const String _storageKey = 'farmer_registration_drafts';

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[DraftService] $message');
    }
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
    final drafts = await _loadDrafts(prefs);

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

    await _saveDrafts(prefs, drafts);
    _log(
      'Saved draft for "${draft.displayName}" '
      '(total drafts: ${drafts.length})',
    );
    return draft.id;
  }

  Future<List<DraftItem>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts(prefs);
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
    final drafts = await _loadDrafts(prefs);
    drafts.removeWhere((d) => d.id == id);
    await _saveDrafts(prefs, drafts);
  }

  Future<List<DraftItem>> _loadDrafts(SharedPreferences prefs) async {
    final raw = prefs.getString(_storageKey);
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
    List<DraftItem> drafts,
  ) async {
    final encoded = jsonEncode(drafts.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
