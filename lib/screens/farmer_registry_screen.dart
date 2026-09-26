import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:convert';
import '../models/farmer_registration_model.dart';
import '../models/draft_item.dart';
import '../models/pending_sync_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../routes/app_routes.dart';
import '../widgets/farmer_personal_info_step.dart';
import '../widgets/farmer_location_step.dart';
import '../widgets/farmer_farm_details_step.dart';
import '../widgets/farm_map_widget.dart';
import '../widgets/farmer_attachments_step.dart';
import '../widgets/farmer_review_step.dart';
import '../widgets/boundary_preview_map.dart';
import '../services/offline_sync_service.dart';
import '../services/draft_service.dart';
import '../theme/app_theme.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[FarmerRegistry] $message');
  }
}

class FarmerRegistryScreen extends StatefulWidget {
  /// If resuming a previously saved draft, pass it here - initState will
  /// restore the wizard's exact state (step data, current step, boundary,
  /// completed steps) so the inspector picks up right where they left off.
  final DraftItem? draftToResume;

  /// If editing an already-queued offline registration (e.g. to remove an
  /// oversized attachment that's been causing sync to time out - see
  /// PendingSyncScreen's "Edit" action), pass it here. initState restores
  /// the full registration snapshot into the wizard (all steps, since a
  /// pending item is a *complete* registration ready to submit, unlike a
  /// draft which may be partial) so the inspector can fix the problem field
  /// and resubmit. On successful resubmission the OLD pending item is
  /// removed so editing doesn't leave a stale duplicate sitting in the
  /// queue alongside the freshly resubmitted one.
  final PendingSyncItem? pendingItemToResume;

  const FarmerRegistryScreen({
    super.key,
    this.draftToResume,
    this.pendingItemToResume,
  });

  @override
  State<FarmerRegistryScreen> createState() => _FarmerRegistryScreenState();
}

class _FarmerRegistryScreenState extends State<FarmerRegistryScreen> {
  int _currentStep = 0;
  final List<bool> _stepCompleted = List.filled(6, false);
  final Map<String, dynamic> _formData = {};
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  final DraftService _draftService = DraftService();
  bool _isSubmitting = false;
  bool _isSavingDraft = false;
  Map<String, dynamic>? _boundaryJson;
  // EUDR Point + Photo mode evidence (set only when that mode was used in
  // the Mapping step). Each entry: {sequence, lat, lng, accuracy,
  // timestamp, photoPath}. Uploaded via a follow-up API call once the
  // farm is created by _submitForm().
  List<Map<String, dynamic>>? _boundaryEvidence;
  // Set once a draft has been saved (or an existing draft is being
  // resumed) - subsequent "Save as Draft" taps update this same record
  // instead of creating a new one each time.
  String? _draftId;
  // Set when resuming from an already-queued PendingSyncItem (see
  // widget.pendingItemToResume) - on successful resubmission, this old
  // item is removed from the offline-sync queue so we don't end up with
  // both the edited version AND the original stuck duplicate.
  String? _editingPendingItemId;

  @override
  void initState() {
    super.initState();
    final draft = widget.draftToResume;
    if (draft != null) {
      _draftId = draft.id;
      _formData.addAll(draft.formData);
      _boundaryJson = draft.boundaryJson;
      _boundaryEvidence = draft.boundaryEvidence;
      _currentStep = draft.currentStep;
      for (
        int i = 0;
        i < _stepCompleted.length && i < draft.stepCompleted.length;
        i++
      ) {
        _stepCompleted[i] = draft.stepCompleted[i];
      }
    }

    final pendingItem = widget.pendingItemToResume;
    if (pendingItem != null && pendingItem.registration != null) {
      _editingPendingItemId = pendingItem.id;
      // registration is FarmerRegistrationModel.toFullJson() - same key
      // shape _formData already uses throughout this screen/its step
      // widgets, so this drops in directly.
      _formData.addAll(pendingItem.registration!);
      final boundaryJsonRaw = pendingItem.registration!['boundaryJson'];
      if (boundaryJsonRaw is String && boundaryJsonRaw.isNotEmpty) {
        try {
          _boundaryJson = jsonDecode(boundaryJsonRaw) as Map<String, dynamic>;
        } catch (_) {
          _boundaryJson = null;
        }
      }
      final evidenceRaw = pendingItem.registration!['boundaryEvidence'];
      if (evidenceRaw is List) {
        _boundaryEvidence = evidenceRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      // A pending item is always a COMPLETE registration (it only exists
      // because a full submission attempt was already made) - mark every
      // step done so the inspector lands straight on Review/Attachments
      // instead of being forced back through steps that are already filled.
      for (int i = 0; i < _stepCompleted.length; i++) {
        _stepCompleted[i] = true;
      }
      // Jump straight to Attachments - this is what the inspector almost
      // always needs to fix (remove/replace an oversized document/photo).
      _currentStep = 4;
    }
  }

  final List<Map<String, String>> _steps = const [
    {'title': 'Personal Info', 'hint': 'Farmer identity and contact'},
    {'title': 'Location & GPS', 'hint': 'County, community, capture GPS'},
    {'title': 'Farm Details', 'hint': 'Crop, ownership, notes'},
    {'title': 'Mapping', 'hint': 'Draw polygon boundary'},
    {'title': 'Attachments', 'hint': 'Photos & consent'},
    {'title': 'Review & Submit', 'hint': 'Check and submit'},
  ];

  void _updateFormData(Map<String, dynamic> data) {
    // Use post-frame callback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _formData.addAll(data);
        });
      }
    });
  }

  /// Returns a specific, user-facing validation error message for [step],
  /// or null if the step's required data is complete (task spec section
  /// 18: "Validation before Ready-to-Sync" - clear error messages instead
  /// of a generic "please complete all fields" toast).
  String? _stepValidationMessage(int step) {
    bool isEmpty(String key) =>
        _formData[key] == null || _formData[key].toString().isEmpty;

    switch (step) {
      case 0: // Personal Info
        if (isEmpty('fullName')) return 'Farmer full name is required.';
        if (isEmpty('gender')) return 'Please select a gender.';
        if (isEmpty('phone')) return 'Phone number is required.';
        if (isEmpty('idType')) return 'Please select an ID type.';
        if (isEmpty('nationalId')) return 'ID Number is required.';
        if (isEmpty('nationalIdPath')) {
          return 'Please capture or upload the ID document.';
        }
        if (isEmpty('farmerPhotoPath')) {
          return "Please capture the farmer's photo.";
        }
        return null;
      case 1: // Location & GPS
        if (isEmpty('county')) return 'Please select a county.';
        if (isEmpty('district')) return 'Please select a district.';
        if (isEmpty('community')) return 'Community is required.';
        if (_formData['lat'] == null || _formData['lng'] == null) {
          return 'GPS location has not been captured. Tap "CAPTURE GPS '
              'LOCATION" before continuing.';
        }
        // Internal integrity guard - inspectorName/enumeratorId are
        // auto-attached from the logged-in session in the background
        // (task spec section 7) and should always be present; if not,
        // the session context was lost and the enumerator must re-login.
        if (isEmpty('inspectorName')) {
          return 'Enumerator identity could not be verified. Please log '
              'in again.';
        }
        return null;
      case 2: // Farm Details
        // Farm name is optional - will be auto-generated if empty
        if (isEmpty('crop')) return 'Please select a crop.';
        if (isEmpty('ownership')) return 'Please select an ownership type.';
        return null;
      case 3: // Mapping
        if (_boundaryJson == null || _boundaryJson!.isEmpty) {
          return 'Please draw the farm boundary on the map.';
        }
        return null;
      case 4: // Attachments
        if (_formData['consent'] != true) {
          return 'Please confirm consent before proceeding.';
        }
        return null;
      case 5: // Review
        return null;
      default:
        return 'This step is not complete.';
    }
  }

  bool _validateStep(int step) => _stepValidationMessage(step) == null;

  void _markStepCompleted(int step) {
    if (_validateStep(step)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _stepCompleted[step] = true;
          });
        }
      });
    }
  }

  void _nextStep() {
    final errorMessage = _stepValidationMessage(_currentStep);
    if (errorMessage == null) {
      _markStepCompleted(_currentStep);
      if (_currentStep < _steps.length - 1) {
        setState(() {
          _currentStep++;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  void _goToStep(int step) {
    // Validate current step before allowing navigation
    if (step <= _currentStep || (step > 0 && _stepCompleted[step - 1])) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  Future<void> _submitForm() async {
    // Validate all steps
    for (int i = 0; i < _steps.length - 1; i++) {
      final errorMessage = _stepValidationMessage(i);
      if (errorMessage != null) {
        setState(() {
          _currentStep = i;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Step ${i + 1}: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Auto-generate farm name if empty
    if (_formData['farmName'] == null ||
        _formData['farmName'].toString().trim().isEmpty) {
      final farmerName = _formData['fullName']?.toString().trim() ?? '';
      final crop = _formData['crop']?.toString().trim() ?? '';
      final community = _formData['community']?.toString().trim() ?? '';

      final parts = <String>[];
      if (farmerName.isNotEmpty) {
        parts.add(farmerName.split(' ').first);
      }
      if (crop.isNotEmpty) parts.add(crop);
      if (community.isNotEmpty) parts.add(community);

      _formData['farmName'] = parts.isEmpty
          ? 'Unnamed Farm'
          : '${parts.join(' ')} Farm';
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final farmerData = FarmerRegistrationModel(
        fullName: _formData['fullName'] ?? '',
        gender: _formData['gender'] ?? '',
        dob: _formData['dob'],
        phone: _formData['phone'] ?? '',
        nationality: _formData['nationality'],
        idType: _formData['idType'],
        idTypeOther: _formData['idTypeOther'],
        nationalId: _formData['nationalId'],
        email: _formData['email'],
        county: _formData['county'] ?? '',
        district: _formData['district'],
        community: _formData['community'] ?? '',
        inspectorName: _formData['inspectorName'] ?? '',
        lat: _formData['lat'],
        lng: _formData['lng'],
        gpsAccuracy: (_formData['gpsAccuracy'] as num?)?.toDouble(),
        gpsCapturedAt: _formData['gpsCapturedAt'],
        directions: _formData['directions'],
        farmName: _formData['farmName'] ?? '',
        crop: _formData['crop'] ?? '',
        ownership: _formData['ownership'] ?? '',
        regStatus: _formData['regStatus'],
        farmSizeManual: _formData['farmSizeManual']?.toString(),
        farmUnitManual: _formData['farmUnitManual'],
        farmNotes: _formData['farmNotes'],
        areaHa: _formData['areaHa']?.toString(),
        areaAc: _formData['areaAc']?.toString(),
        boundaryJson: _boundaryJson != null ? jsonEncode(_boundaryJson) : null,
        boundaryEvidence: _boundaryEvidence,
        consent: _formData['consent'] ?? false,
        farmerPhotoPath: _formData['farmerPhotoPath'],
        nationalIdPath: _formData['nationalIdPath'],
        farmSelfiePath: _formData['farmSelfiePath'],
        farmPhotosPaths: _formData['farmPhotosPaths'] != null
            ? List<String>.from(_formData['farmPhotosPaths'])
            : null,
        complianceDocuments: _formData['complianceDocuments'] != null
            ? (_formData['complianceDocuments'] as List)
                  .map((e) => Map<String, String>.from(e as Map))
                  .toList()
            : null,
        cooperativeName: _formData['cooperativeName'],
        cooperativeId: _formData['cooperativeId'],
        cooperativeSource: _formData['cooperativeSource'],
        enumeratorId: _formData['enumeratorId'],
        numberOfTrees: _formData['numberOfTrees']?.toString(),
        yearsInCultivation: _formData['yearsInCultivation']?.toString(),
        harvestSeason: _formData['harvestSeason'],
        averageYield: _formData['averageYield'],
        buyers: _formData['buyers'],
        useChemicals: _formData['useChemicals'] ?? false,
        extensionServices: _formData['extensionServices'] ?? false,
        farmAddress: _formData['farmAddress'],
        signaturePath: _formData['signaturePath'],
      );

      // If the device has no connectivity at all, don't even attempt the
      // live submission - go straight to the offline queue so the
      // inspector isn't stuck waiting on a call that can't succeed.
      final hasConnectivity = await _offlineSyncService.hasConnectivity();
      if (!hasConnectivity) {
        await _offlineSyncService.enqueue(farmerData);
        await _discardDraftIfAny();
        await _removeOldPendingItemIfEditing();
        if (mounted) {
          _showQueuedForSyncMessage();
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
        }
        return;
      }

      try {
        final token = await _authService.getToken();
        final response = await _apiService.registerFarmer(
          farmerData: farmerData,
          authToken: token,
        );

        // If EUDR Point + Photo evidence was captured, attach it now via a
        // follow-up call using the newly created farm's id (returned in
        // response['data']['farmId']). This is best-effort: the farmer/farm
        // record itself is already saved at this point, so a failure here
        // is surfaced as a warning rather than blocking navigation - the
        // inspector can re-attempt evidence upload later if needed.
        if (_boundaryEvidence != null && _boundaryEvidence!.isNotEmpty) {
          try {
            final data = response['data'];
            final farmId = data is Map ? data['farmId'] as String? : null;
            if (farmId != null) {
              await _apiService.addBoundaryEvidence(
                farmId: farmId,
                points: _boundaryEvidence!,
                authToken: token,
              );
            } else {
              _log(
                'No farmId returned from registerFarmer - '
                'boundary evidence not attached.',
              );
            }
          } catch (evidenceError) {
            _log('Failed to attach boundary evidence: $evidenceError');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Farmer registered, but boundary evidence photos '
                    'failed to upload: ${evidenceError.toString()}',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        }

        await _discardDraftIfAny();
        await _removeOldPendingItemIfEditing();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Farmer registered successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back to dashboard/home screen
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
        }
      } catch (e) {
        // Distinguish network failures (server unreachable / timed out)
        // from genuine validation errors returned by the backend. Only
        // network failures get queued for later retry - validation errors
        // (e.g. duplicate national ID) need the inspector to fix the form.
        if (_isNetworkError(e)) {
          await _offlineSyncService.enqueue(farmerData);
          await _discardDraftIfAny();
          await _removeOldPendingItemIfEditing();
          if (mounted) {
            _showQueuedForSyncMessage();
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// Saves the wizard's current state (whatever has been filled in so
  /// far, at any step) as a draft, without validating or submitting
  /// anything. Called by the "Save as Draft" button so an inspector who
  /// runs out of time in the field - or is waiting on the farmer to find
  /// a missing document - doesn't lose their progress.
  Future<void> _saveAsDraft() async {
    final hasAnyName = (_formData['fullName'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    if (!hasAnyName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter at least the farmer\'s name before saving as a draft.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSavingDraft = true;
    });

    try {
      final id = await _draftService.saveDraft(
        id: _draftId,
        formData: _formData,
        boundaryJson: _boundaryJson,
        boundaryEvidence: _boundaryEvidence,
        currentStep: _currentStep,
        stepCompleted: _stepCompleted,
      );
      _draftId = id;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Draft saved. Resume it anytime from "Drafts" on the dashboard.',
            ),
            backgroundColor: Colors.blueGrey,
          ),
        );
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save draft: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDraft = false;
        });
      }
    }
  }

  /// If this registration was resumed from a saved draft, removes that
  /// draft now that it has either been submitted successfully or queued
  /// for offline sync - it's no longer "in progress", so it shouldn't
  /// keep cluttering the Drafts list.
  Future<void> _discardDraftIfAny() async {
    if (_draftId != null) {
      await _draftService.deleteDraft(_draftId!);
    }
  }

  /// If this registration was resumed from an already-queued
  /// PendingSyncItem (see widget.pendingItemToResume), removes that OLD
  /// item now that a fresh copy has just been submitted (either
  /// successfully, or re-queued offline). Without this, editing a stuck
  /// item would leave the original broken copy sitting in the queue
  /// alongside the fixed one, showing as a confusing duplicate.
  Future<void> _removeOldPendingItemIfEditing() async {
    if (_editingPendingItemId != null) {
      await _offlineSyncService.removeItem(_editingPendingItemId!);
    }
  }

  bool _isNetworkError(Object e) {
    final message = e.toString().toLowerCase();
    return message.contains('network error') ||
        message.contains('socketexception') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  void _showQueuedForSyncMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No connection - farmer saved locally and will sync automatically '
          'once you\'re back online.',
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _updateBoundary(Map<String, dynamic> boundary) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _boundaryJson = boundary;
          if (boundary.isNotEmpty) {
            _formData['boundaryJson'] = jsonEncode(boundary);
          }
        });
      }
    });
  }

  void _updateArea(double areaHa, double areaAc) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _formData['areaHa'] = areaHa.toStringAsFixed(4);
          _formData['areaAc'] = areaAc.toStringAsFixed(4);
        });
      }
    });
  }

  // Stores the EUDR Point + Photo per-point evidence (GPS + local photo
  // path per point) captured by FarmMapWidget, so it can be uploaded via a
  // follow-up API call once the farm is created in _submitForm().
  void _updateBoundaryEvidence(List<Map<String, dynamic>> evidence) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _boundaryEvidence = evidence.isNotEmpty ? evidence : null;
        });
      }
    });
  }

  Widget _buildMappingStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.paleGreen,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Farm Boundary Mapping',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the button below to open the map in full screen. Search for a location, then start drawing the farm boundary by tapping points on the map.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<Map<String, dynamic>>(
                        MaterialPageRoute(
                          builder: (context) => FarmMapWidget(
                            initialLat: _formData['lat'],
                            initialLng: _formData['lng'],
                            onBoundaryDrawn: (boundary) {
                              // This will be called during drawing
                            },
                            onAreaCalculated: (areaHa, areaAc) {
                              // This will be called during drawing
                            },
                            onBoundaryEvidenceCaptured: (evidence) {
                              // This will be called when EUDR Point + Photo
                              // mode finishes
                            },
                          ),
                        ),
                      );

                  if (result != null && result['boundary'] != null) {
                    _updateBoundary(result['boundary'] as Map<String, dynamic>);
                    if (result['areaHa'] != null) {
                      _updateArea(
                        (result['areaHa'] as num).toDouble(),
                        (result['areaAc'] as num?)?.toDouble() ?? 0.0,
                      );
                    }
                    // EUDR Point + Photo mode returns per-point geotagged
                    // evidence (each with a local photo path) alongside the
                    // boundary - store it so it can be uploaded via a
                    // follow-up call once the farm is created.
                    final evidence = result['boundaryEvidence'];
                    if (evidence != null && evidence is List) {
                      _updateBoundaryEvidence(
                        evidence.whereType<Map<String, dynamic>>().toList(),
                      );
                    } else {
                      _updateBoundaryEvidence(const []);
                    }
                  }
                },
                icon: const Icon(Icons.map),
                label: const Text('Open Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_boundaryJson != null && _boundaryJson!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.successBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Boundary Captured',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success,
                            ),
                          ),
                          if (_formData['areaHa'] != null)
                            Text(
                              'Area: ${_formData['areaHa']} hectares',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (_boundaryEvidence != null &&
                              _boundaryEvidence!.isNotEmpty)
                            Text(
                              'EUDR evidence: ${_boundaryEvidence!.length} '
                              'geotagged photos attached',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Visual confirmation of the drawn area over satellite
                // imagery, shown right after capture - before the mapper
                // moves on to Attachments / Review & Submit.
                BoundaryPreviewMap(boundaryJson: _boundaryJson!),
              ],
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No boundary captured yet. Tap "Open Map" to start mapping.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return FarmerPersonalInfoStep(
          onDataChanged: _updateFormData,
          initialData: _formData,
        );
      case 1:
        return FarmerLocationStep(
          onDataChanged: _updateFormData,
          initialData: _formData,
        );
      case 2:
        return FarmerFarmDetailsStep(
          onDataChanged: _updateFormData,
          initialData: _formData,
        );
      case 3:
        return _buildMappingStep();
      case 4:
        return FarmerAttachmentsStep(
          onDataChanged: _updateFormData,
          initialData: _formData,
        );
      case 5:
        return FarmerReviewStep(formData: _formData, boundaryJson: _boundaryJson);
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepIndicator(bool isMobile) {
    if (isMobile) {
      // Mobile: Horizontal scrollable step indicator at top
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: const Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_steps.length, (index) {
              final isActive = index == _currentStep;
              final isDone = _stepCompleted[index];
              return GestureDetector(
                onTap: () => _goToStep(index),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.primaryGreen
                        : (isDone ? AppTheme.paleGreen : AppTheme.divider),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isActive || isDone
                              ? Colors.white
                              : AppTheme.textMuted,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            isDone ? '✓' : '${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: isActive || isDone
                                  ? AppTheme.primaryGreen
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isActive || !isMobile)
                        Text(
                          _steps[index]['title']!,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: isActive
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      );
    } else {
      // Desktop: Vertical sidebar
      return Container(
        width: 280,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(right: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.paleGreen,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Liberia Agriculture Commodity Regulatory Authority LACRA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Complete each section and click Next. Sections marked done are ready.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final isActive = index == _currentStep;
                  final isDone = _stepCompleted[index];
                  return InkWell(
                    onTap: () => _goToStep(index),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.paleGreen : Colors.transparent,
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primaryGreen.withValues(alpha: 0.5)
                              : AppTheme.border,
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                                  : AppTheme.paleGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDone
                                    ? AppTheme.primaryGreen
                                    : AppTheme.textMuted,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                isDone ? '✓' : '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: isDone
                                      ? AppTheme.primaryGreen
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _steps[index]['title']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: isActive
                                        ? AppTheme.darkGreen
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  _steps[index]['hint']!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Farmer Registry'),
      // ),
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      backgroundColor: AppTheme.background,
      bottomNavigationBar: isMobile
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: const Border(top: BorderSide(color: AppTheme.border)),
                boxShadow: AppTheme.softShadow,
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _isSavingDraft ? null : _saveAsDraft,
                      icon: _isSavingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        _isSavingDraft ? 'Saving...' : 'Save as Draft',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _currentStep > 0 ? _previousStep : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _currentStep < _steps.length - 1
                                ? _nextStep
                                : (_isSubmitting ? null : _submitForm),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    _currentStep < _steps.length - 1
                                        ? 'Next'
                                        : 'Submit',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildStepIndicator(true),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _buildStepIndicator(false),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildStepContent(),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _isSavingDraft ? null : _saveAsDraft,
                      icon: _isSavingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        _isSavingDraft ? 'Saving...' : 'Save as Draft',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: _currentStep > 0 ? _previousStep : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _currentStep < _steps.length - 1
                          ? _nextStep
                          : (_isSubmitting ? null : _submitForm),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _currentStep < _steps.length - 1
                                  ? 'Next'
                                  : 'Submit',
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
