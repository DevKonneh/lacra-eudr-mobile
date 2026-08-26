/// Represents an in-progress farmer registration that the inspector
/// explicitly chose to "Save as Draft" instead of submitting - e.g. they
/// ran out of time in the field, or are waiting on the farmer to find a
/// missing document. Unlike [PendingSyncItem] (which is only ever created
/// automatically when a *submission* has no connectivity or fails), a
/// draft is created on-demand by the inspector at any point in the wizard
/// and can be resumed and edited later before it's ever submitted.
///
/// Stores the raw wizard state - [formData] (the free-form step data map,
/// including any local file paths already picked), [boundaryJson]/
/// [boundaryEvidence] (farm boundary mapping state), [currentStep] and
/// [stepCompleted] (so resuming drops the inspector back exactly where
/// they left off) - all persisted locally via [DraftService] (shared_
/// preferences). Drafts never touch the backend; they only become a real
/// submission (or a [PendingSyncItem] if offline) once the inspector taps
/// "Submit" after resuming.
class DraftItem {
  final String id;
  final Map<String, dynamic> formData;
  final Map<String, dynamic>? boundaryJson;
  final List<Map<String, dynamic>>? boundaryEvidence;
  final int currentStep;
  final List<bool> stepCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  DraftItem({
    required this.id,
    required this.formData,
    this.boundaryJson,
    this.boundaryEvidence,
    required this.currentStep,
    required this.stepCompleted,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Best-effort display name for the drafts list UI.
  String get displayName {
    final name = (formData['fullName'] ?? '').toString().trim();
    return name.isEmpty ? 'Unnamed farmer (draft)' : name;
  }

  /// Best-effort subtitle (community/county) for the drafts list UI.
  String? get locationSummary {
    final community = (formData['community'] ?? '').toString().trim();
    final county = (formData['county'] ?? '').toString().trim();
    final parts = [community, county].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  int get completedStepCount => stepCompleted.where((c) => c).length;

  factory DraftItem.fromJson(Map<String, dynamic> json) {
    return DraftItem(
      id: json['id'] as String,
      formData: Map<String, dynamic>.from(json['formData'] as Map? ?? {}),
      boundaryJson: json['boundaryJson'] != null
          ? Map<String, dynamic>.from(json['boundaryJson'] as Map)
          : null,
      boundaryEvidence: (json['boundaryEvidence'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      currentStep: json['currentStep'] as int? ?? 0,
      stepCompleted:
          (json['stepCompleted'] as List<dynamic>?)
              ?.map((e) => e as bool)
              .toList() ??
          List.filled(6, false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'formData': formData,
      if (boundaryJson != null) 'boundaryJson': boundaryJson,
      if (boundaryEvidence != null) 'boundaryEvidence': boundaryEvidence,
      'currentStep': currentStep,
      'stepCompleted': stepCompleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
