import 'package:flutter/material.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/boundary_preview_map.dart';
import '../widgets/farm_map_widget.dart';
import '../widgets/status_badge.dart';

/// Lets an enumerator/inspector RE-WALK an EXISTING farm's boundary and
/// submit fresh EUDR-standard point+photo evidence, replacing the
/// previously stored polygon via PUT /farms/:id/boundary-evidence
/// (backend FarmController.addBoundaryEvidence - already supports this,
/// see ApiService.addBoundaryEvidence doc comment).
///
/// This is distinct from AddFarmScreen (which creates a brand-new farm):
/// here the farm already exists, we only replace its boundary + area, and
/// the backend re-runs GPS polygon/area geometry validation
/// (GeometryValidationService via FarmGeometryHelper.validateAndAnnotateFarm)
/// as part of saving - we surface that fresh result to the user immediately
/// after submit (gap #3 from the mobile gap analysis: "surface geometry
/// validation feedback"), rather than silently succeeding with a boundary
/// the backend may have flagged as Needs Review/overlapping.
///
/// Flow:
///   1. Show the farm's CURRENT boundary (read-only preview) so the user
///      can confirm which farm/shape they're about to replace.
///   2. "Re-map Boundary" opens FarmMapWidget forced into EUDR Point+Photo
///      mode (the only mode addBoundaryEvidence's backend contract
///      accepts - at least 4 geotagged points, each with a photo).
///   3. On submit, PUT the new points+photos, then immediately call
///      POST /farms/:id/geometry/revalidate... actually the boundary-
///      evidence endpoint already returns the updated farm (with its
///      freshly computed geometryStatus etc. baked in by the backend's
///      own validateAndAnnotateFarm call during save when `location` is
///      included) - we parse that response straight into a FarmRecord and
///      show a clear Valid / Needs Review / Invalid banner with the exact
///      errors/warnings instead of just "Success".
class EditBoundaryScreen extends StatefulWidget {
  final FarmRecord farm;
  final String farmerName;

  const EditBoundaryScreen({
    super.key,
    required this.farm,
    required this.farmerName,
  });

  @override
  State<EditBoundaryScreen> createState() => _EditBoundaryScreenState();
}

class _EditBoundaryScreenState extends State<EditBoundaryScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _newBoundaryJson;
  List<Map<String, dynamic>>? _newBoundaryEvidence;
  double _newAreaHa = 0.0;
  bool _isSubmitting = false;
  String? _error;

  // Populated from the backend response right after a successful submit,
  // so the Needs Review / Invalid feedback is this screen's own
  // authoritative result, not the farm's previous (now stale) status.
  FarmRecord? _resultFarm;

  double? get _currentLat {
    try {
      final coords = widget.farm.location?['coordinates'] as List?;
      final ring = coords != null && coords.isNotEmpty
          ? coords[0] as List
          : null;
      if (ring == null || ring.isEmpty) return null;
      final first = ring[0] as List;
      return (first[1] as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  double? get _currentLng {
    try {
      final coords = widget.farm.location?['coordinates'] as List?;
      final ring = coords != null && coords.isNotEmpty
          ? coords[0] as List
          : null;
      if (ring == null || ring.isEmpty) return null;
      final first = ring[0] as List;
      return (first[0] as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openRemapScreen() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) =>
            FarmMapWidget(initialLat: _currentLat, initialLng: _currentLng),
      ),
    );
    if (result == null) return;

    final evidence = result['boundaryEvidence'];
    if (evidence == null) {
      // User saved in Manual/Auto-Walk mode instead of Point+Photo - the
      // backend's addBoundaryEvidence endpoint requires per-point photos,
      // so a plain polygon (no evidence) cannot be submitted here.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please use "EUDR Point + Photo" mode (tap the mode toggle) to '
            're-map a boundary - each point needs a photo for evidence.',
          ),
          backgroundColor: AppTheme.warning,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _newBoundaryJson = result['boundary'] as Map<String, dynamic>?;
      _newBoundaryEvidence = (evidence as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      _newAreaHa = (result['areaHa'] as num?)?.toDouble() ?? 0.0;
      _resultFarm = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final evidence = _newBoundaryEvidence;
    if (evidence == null || evidence.isEmpty) {
      setState(() => _error = 'Please re-map the boundary before saving.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final token = await _authService.getToken();
      final response = await _apiService.addBoundaryEvidence(
        farmId: widget.farm.id,
        points: evidence,
        authToken: token,
        location: _newBoundaryJson,
        totalAreaHa: _newAreaHa > 0 ? _newAreaHa : null,
      );

      final data = response['data'];
      final updatedFarm = data is Map<String, dynamic>
          ? FarmRecord.fromJson(data)
          : null;

      if (!mounted) return;
      setState(() {
        _resultFarm = updatedFarm;
        _isSubmitting = false;
      });

      if (updatedFarm != null) {
        final isGood = updatedFarm.geometryStatus == FarmGeometryStatus.valid;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isGood
                  ? 'Boundary updated and validated successfully.'
                  : 'Boundary saved - please review the flags below.',
            ),
            backgroundColor: isGood ? AppTheme.success : AppTheme.warning,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  void _done() {
    // Pop true only once the user has seen the result and chosen to leave,
    // so FarmerDetailScreen knows to refresh and show the new boundary.
    Navigator.of(context).pop(_resultFarm != null);
  }

  Widget _geometryFeedbackCard(FarmRecord farm) {
    final status = farm.geometryStatus;
    final isInvalid = status == FarmGeometryStatus.invalid;
    final isReview = status == FarmGeometryStatus.needsReview;
    final bannerColor = isInvalid
        ? AppTheme.dangerBg
        : isReview
        ? AppTheme.warningBg
        : AppTheme.successBg;
    final iconColor = isInvalid
        ? AppTheme.danger
        : isReview
        ? AppTheme.warning
        : AppTheme.success;
    final icon = isInvalid
        ? Icons.error_outline
        : isReview
        ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isInvalid
                      ? 'Boundary failed validation'
                      : isReview
                      ? 'Boundary needs review'
                      : 'Boundary validated successfully',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatusBadge(label: status.label),
              if (farm.overlapsExistingFarm) ...[
                const SizedBox(width: 8),
                const StatusBadge(label: 'Overlap Detected'),
              ],
            ],
          ),
          if (farm.calculatedAreaHa != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.straighten,
                  size: 15,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Calculated area: ${farm.calculatedAreaHa!.toStringAsFixed(2)} ha',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (farm.areaDifferencePercent != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.compare_arrows,
                  size: 15,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Area difference: ${farm.areaDifferencePercent!.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (farm.gpsAccuracyM != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.gps_fixed,
                  size: 15,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'GPS accuracy: ±${farm.gpsAccuracyM!.toStringAsFixed(1)} m',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (farm.geometryErrors.isNotEmpty ||
              farm.geometryWarnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...farm.geometryErrors.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: AppTheme.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...farm.geometryWarnings.map(
              (w) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      size: 14,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _resultFarm == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text('Edit Boundary - ${widget.farm.name}'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.danger,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Result banner replaces the capture UI once submit succeeds,
              // so the user's attention goes straight to the validation
              // outcome rather than the stale "before" state below it.
              if (_resultFarm != null) ...[
                _geometryFeedbackCard(_resultFarm!),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _done,
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          setState(() {
                            _resultFarm = null;
                            _newBoundaryJson = null;
                            _newBoundaryEvidence = null;
                            _newAreaHa = 0.0;
                          });
                        },
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Text('Re-map Again'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Current Boundary',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          StatusBadge(label: widget.farm.geometryStatus.label),
                        ],
                      ),
                      const Divider(height: 20),
                      if (widget.farm.location != null)
                        BoundaryPreviewMap(
                          boundaryJson: {'geometry': widget.farm.location},
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No boundary recorded yet for this farm.',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                      if (widget.farm.totalAreaHa != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.straighten,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.farm.totalAreaHa} ha (declared)',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Boundary',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Re-walk the farm perimeter using EUDR Point + Photo '
                        'mode (at least 4 geotagged points, each with a '
                        'photo). This REPLACES the farm\'s stored boundary.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_newBoundaryJson != null) ...[
                        BoundaryPreviewMap(boundaryJson: _newBoundaryJson!),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.straighten,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_newAreaHa.toStringAsFixed(4)} ha · '
                              '${_newBoundaryEvidence?.length ?? 0} points captured',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _openRemapScreen,
                        icon: Icon(
                          _newBoundaryJson == null
                              ? Icons.map
                              : Icons.edit_location_alt,
                        ),
                        label: Text(
                          _newBoundaryJson == null
                              ? 'Re-map Boundary'
                              : 'Re-walk Again',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_isSubmitting || _newBoundaryEvidence == null)
                      ? null
                      : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save New Boundary'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
