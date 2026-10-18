import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/farm_map_widget.dart';
import '../widgets/farmer_farm_details_step.dart';
import '../widgets/boundary_preview_map.dart';

/// Lets an enumerator attach a NEW farm to an ALREADY-REGISTERED farmer
/// (task: "Farm Mapping App" gap - previously the only way to add a
/// second/third plot for a farmer was to re-register them from scratch).
/// Reuses the exact same [FarmerFarmDetailsStep] + [FarmMapWidget] capture
/// flow used inside the new-farmer registration wizard, scoped down to
/// just one farm, then POSTs it via [ApiService.createFarmForFarmer] -
/// backend FarmController.create() already supports this via `farmerId`
/// (see its "Add Farm to Existing Farmer" audit-log comment), so no
/// backend change was needed, only this missing mobile screen.
class AddFarmScreen extends StatefulWidget {
  final String farmerId;
  final String farmerName;

  const AddFarmScreen({
    super.key,
    required this.farmerId,
    required this.farmerName,
  });

  @override
  State<AddFarmScreen> createState() => _AddFarmScreenState();
}

class _AddFarmScreenState extends State<AddFarmScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  Map<String, dynamic> _farmData = {};
  Map<String, dynamic>? _boundaryJson;
  bool _isSubmitting = false;
  String? _error;

  void _onDetailsChanged(Map<String, dynamic> data) {
    setState(() {
      _farmData = {..._farmData, ...data};
    });
  }

  void _updateBoundary(Map<String, dynamic> boundary) {
    setState(() {
      _boundaryJson = boundary.isNotEmpty ? boundary : null;
    });
  }

  void _updateArea(double areaHa, double areaAc) {
    setState(() {
      _farmData['areaHa'] = areaHa > 0 ? areaHa.toStringAsFixed(4) : null;
      _farmData['areaAc'] = areaAc > 0 ? areaAc.toStringAsFixed(4) : null;
    });
  }

  Future<void> _openMap() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => const FarmMapWidget(),
      ),
    );
    if (result == null) return;
    if (result['boundary'] != null) {
      _updateBoundary(result['boundary'] as Map<String, dynamic>);
    }
    if (result['areaHa'] != null) {
      _updateArea(
        (result['areaHa'] as num).toDouble(),
        (result['areaAc'] as num?)?.toDouble() ?? 0.0,
      );
    }
  }

  bool _validateDetails() {
    final crop = (_farmData['crop'] ?? '').toString();
    final ownership = (_farmData['ownership'] ?? '').toString();
    if (crop.isEmpty) {
      _showError('Please select a primary crop.');
      return false;
    }
    if (ownership.isEmpty) {
      _showError('Please select an ownership type.');
      return false;
    }
    if (_boundaryJson == null || _boundaryJson!.isEmpty) {
      _showError('Please map the farm boundary before submitting.');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _submit() async {
    if (!_validateDetails()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final token = await _authService.getToken();
      final farmDetails = {
        ..._farmData,
        'boundaryJson': _boundaryJson != null
            ? jsonEncode(_boundaryJson)
            : null,
      };
      await _apiService.createFarmForFarmer(
        farmerId: widget.farmerId,
        farmDetails: farmDetails,
        authToken: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Farm added successfully.'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Add Farm - ${widget.farmerName}'),
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
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
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
                    'Farm Details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Divider(height: 20),
                  FarmerFarmDetailsStep(onDataChanged: _onDetailsChanged),
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
                    'Farm Boundary',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  if (_boundaryJson != null) ...[
                    BoundaryPreviewMap(boundaryJson: _boundaryJson!),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          _farmData['areaHa'] != null
                              ? '${_farmData['areaHa']} ha'
                              : 'Area calculated',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _openMap,
                    icon: Icon(_boundaryJson == null ? Icons.map : Icons.edit_location_alt),
                    label: Text(_boundaryJson == null ? 'Map Boundary' : 'Re-map Boundary'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
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
                  : const Text('Add Farm'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

