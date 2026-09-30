import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:convert';
import '../models/farmer_registration_model.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../routes/app_routes.dart';
import '../widgets/farmer_personal_info_step.dart';
import '../widgets/farmer_location_step.dart';
import '../widgets/farmer_farm_details_step.dart';
import '../widgets/farm_map_widget.dart';
import '../widgets/farmer_attachments_step.dart';
import '../widgets/farmer_review_step.dart';
import '../widgets/geoid_farm_qr_widget.dart';
import '../services/offline_sync_service.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[FarmerRegistry] $message');
  }
}

class FarmerRegistryScreen extends StatefulWidget {
  const FarmerRegistryScreen({super.key});

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
  bool _isSubmitting = false;
  Map<String, dynamic>? _boundaryJson;
  // EUDR Point + Photo mode evidence (set only when that mode was used in
  // the Mapping step). Each entry: {sequence, lat, lng, accuracy,
  // timestamp, photoPath}. Uploaded via a follow-up API call once the
  // farm is created by _submitForm().
  List<Map<String, dynamic>>? _boundaryEvidence;

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

  bool _validateStep(int step) {
    switch (step) {
      case 0: // Personal Info
        return _formData['fullName'] != null &&
            _formData['fullName'].toString().isNotEmpty &&
            _formData['gender'] != null &&
            _formData['gender'].toString().isNotEmpty &&
            _formData['phone'] != null &&
            _formData['phone'].toString().isNotEmpty;
      case 1: // Location & GPS
        return _formData['county'] != null &&
            _formData['county'].toString().isNotEmpty &&
            _formData['community'] != null &&
            _formData['community'].toString().isNotEmpty &&
            _formData['inspectorName'] != null &&
            _formData['inspectorName'].toString().isNotEmpty;
      case 2: // Farm Details
        // Farm name is optional - will be auto-generated if empty
        return _formData['crop'] != null &&
            _formData['crop'].toString().isNotEmpty &&
            _formData['ownership'] != null &&
            _formData['ownership'].toString().isNotEmpty;
      case 3: // Mapping
        return _boundaryJson != null && _boundaryJson!.isNotEmpty;
      case 4: // Attachments
        return _formData['consent'] == true;
      case 5: // Review
        return true;
      default:
        return false;
    }
  }

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
    if (_validateStep(_currentStep)) {
      _markStepCompleted(_currentStep);
      if (_currentStep < _steps.length - 1) {
        setState(() {
          _currentStep++;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields'),
          backgroundColor: Colors.red,
        ),
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
      if (!_validateStep(i)) {
        setState(() {
          _currentStep = i;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please complete step ${i + 1}'),
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
      );

      // If the device has no connectivity at all, don't even attempt the
      // live submission - go straight to the offline queue so the
      // inspector isn't stuck waiting on a call that can't succeed.
      final hasConnectivity = await _offlineSyncService.hasConnectivity();
      if (!hasConnectivity) {
        await _offlineSyncService.enqueue(farmerData);
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

        if (mounted) {
          await _showRegistrationSuccessSheet(response);
        }
      } catch (e) {
        // Distinguish network failures (server unreachable / timed out)
        // from genuine validation errors returned by the backend. Only
        // network failures get queued for later retry - validation errors
        // (e.g. duplicate national ID) need the inspector to fix the form.
        if (_isNetworkError(e)) {
          await _offlineSyncService.enqueue(farmerData);
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

  /// Show the post-registration success bottom sheet with GeoID + farm QR.
  ///
  /// Extracts farm data from the API response:
  ///   response['data']['farms'][0]  — preferred path
  ///   response['data']              — fallback (older backend format)
  ///
  /// GeoID fields are best-effort — backend mints async, may be null.
  /// After the inspector taps "Done" (or dismisses), we navigate to dashboard.
  Future<void> _showRegistrationSuccessSheet(
    Map<String, dynamic> response,
  ) async {
    // ── Extract farmer name ──────────────────────────────────────────────────
    final farmerName =
        _formData['fullName']?.toString().trim() ?? 'New Farmer';

    // ── Extract farm fields from response ────────────────────────────────────
    String farmId = '';
    String? geoId;
    String? geoIdUri;
    String? farmQrCode;

    try {
      final data = response['data'];
      Map<String, dynamic>? farmJson;

      if (data is Map<String, dynamic>) {
        // Primary path: data.farms[0]
        final farms = data['farms'];
        if (farms is List && farms.isNotEmpty && farms[0] is Map) {
          farmJson = Map<String, dynamic>.from(farms[0] as Map);
        } else {
          // Fallback: the data map itself may be the farm
          farmJson = data;
        }
      }

      if (farmJson != null) {
        farmId = farmJson['id']?.toString() ??
            farmJson['farmId']?.toString() ??
            '';
        geoId = farmJson['geoId']?.toString();
        geoIdUri = farmJson['geoIdUri']?.toString();
        farmQrCode = farmJson['farmQrCode']?.toString();
      }
    } catch (e) {
      _log('Could not extract farm data from response: $e');
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _RegistrationSuccessSheet(
        farmerName: farmerName,
        farmId: farmId,
        geoId: geoId,
        geoIdUri: geoIdUri,
        farmQrCode: farmQrCode,
        onDone: () {
          Navigator.of(ctx).pop();
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
        },
      ),
    );
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
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Farm Boundary Mapping',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the button below to open the map in full screen. Search for a location, then start drawing the farm boundary by tapping points on the map.',
                style: TextStyle(fontSize: 13),
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
                        evidence
                            .whereType<Map<String, dynamic>>()
                            .toList(),
                      );
                    } else {
                      _updateBoundaryEvidence(const []);
                    }
                  }
                },
                icon: const Icon(Icons.map),
                label: const Text('Open Map'),
                style: ElevatedButton.styleFrom(
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
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Boundary Captured',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
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
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No boundary captured yet. Tap "Open Map" to start mapping.',
                    style: TextStyle(fontSize: 12),
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
        return FarmerReviewStep(formData: _formData);
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
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
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
                        ? const Color(0xFF4CAF50)
                        : (isDone
                              ? Colors.green.shade100
                              : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(20),
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
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            isDone ? '✓' : '${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: isActive || isDone
                                  ? const Color(0xFF4CAF50)
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
                            color: isActive ? Colors.white : Colors.black87,
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
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(right: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
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
                      color: const Color(0xFF4CAF50).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                      ),
                    ),
                    child: const Text(
                      'Liberia Agriculture Commodity Regulatory Authority LACRA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Complete each section and click Next. Sections marked done are ready.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
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
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF4CAF50).withOpacity(0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF4CAF50).withOpacity(0.5)
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFF4CAF50).withOpacity(0.2)
                                  : const Color(0xFF4CAF50).withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey.shade400,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                isDone ? '✓' : '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: isDone
                                      ? const Color(0xFF4CAF50)
                                      : Colors.grey.shade700,
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
                                        ? const Color(0xFF4CAF50)
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _steps[index]['hint']!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF757575),
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
      bottomNavigationBar: isMobile
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _currentStep > 0 ? _previousStep : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
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
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: _currentStep > 0 ? _previousStep : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
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

// ─────────────────────────────────────────────────────────────────────────────
// Post-registration success bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Shown after a successful farmer registration.
///
/// Displays:
///   • A green success header with the farmer name
///   • The [GeoIdFarmQrWidget] (GeoID card + farm QR)
///   • A "Done" button that dismisses the sheet and navigates to dashboard
///
/// All GeoID fields are best-effort — gracefully shows a "pending" state
/// if the backend hasn't minted the GeoID yet.
class _RegistrationSuccessSheet extends StatelessWidget {
  const _RegistrationSuccessSheet({
    required this.farmerName,
    required this.farmId,
    required this.geoId,
    required this.geoIdUri,
    required this.farmQrCode,
    required this.onDone,
  });

  final String farmerName;
  final String farmId;
  final String? geoId;
  final String? geoIdUri;
  final String? farmQrCode;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Success header ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2E7D32),
                  const Color(0xFF4CAF50).withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Registration Successful',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  farmerName,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    geoId != null
                        ? 'FAO GeoID minted — farm is EUDR-ready'
                        : 'GeoID pending — will mint automatically',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── GeoID + QR section (scrollable) ───────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: farmId.isNotEmpty
                  ? GeoIdFarmQrWidget(
                      farmId: farmId,
                      geoId: geoId,
                      geoIdUri: geoIdUri,
                      farmQrCode: farmQrCode,
                    )
                  : _buildNoFarmIdFallback(),
            ),
          ),

          // ── EUDR note ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Share the farm QR with buyers and auditors. '
                    'The public view shows only geo data — no personal info.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Done button ───────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Done — Go to Dashboard'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fallback when the backend didn't return a farm ID in the response.
  Widget _buildNoFarmIdFallback() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 48),
          const SizedBox(height: 12),
          const Text(
            'Farmer Registered Successfully',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The GeoID and farm QR code will be available in the '
            'farmer detail view once the backend has processed the submission.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
