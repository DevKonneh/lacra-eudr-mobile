import 'package:flutter/material.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'add_farm_screen.dart';

/// Full detail view for a single farmer + their farm(s), fetched fresh
/// from GET /api/farmers/:id. Reached by tapping a row in FarmersListScreen.
class FarmerDetailScreen extends StatefulWidget {
  final String farmerId;

  const FarmerDetailScreen({super.key, required this.farmerId});

  @override
  State<FarmerDetailScreen> createState() => _FarmerDetailScreenState();
}

class _FarmerDetailScreenState extends State<FarmerDetailScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  FarmerRecord? _farmer;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await _authService.getToken();
      final farmer = await _apiService.getFarmer(
        id: widget.farmerId,
        authToken: token,
      );
      if (!mounted) return;
      setState(() {
        _farmer = farmer;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _addFarm() async {
    final farmer = _farmer;
    if (farmer == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AddFarmScreen(
          farmerId: farmer.id,
          farmerName: farmer.fullName,
        ),
      ),
    );
    if (added == true) {
      _load();
    }
  }

  Widget _infoRow(String label, String? value, {IconData? icon}) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.paleGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppTheme.primaryGreen),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_farmer?.fullName ?? 'Farmer Details'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: (!_isLoading && _error == null && _farmer != null)
          ? FloatingActionButton.extended(
              onPressed: _addFarm,
              backgroundColor: AppTheme.primaryGreen,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add Farm'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: AppTheme.dangerBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final farmer = _farmer!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.white,
                  child: Text(
                    farmer.fullName.isNotEmpty
                        ? farmer.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  farmer.fullName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (farmer.farmerId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    farmer.farmerId!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                StatusBadge(label: farmer.identityStatus),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            title: 'Personal Information',
            icon: Icons.badge_outlined,
            children: [
              _infoRow(
                'Farmer ID',
                farmer.farmerId,
                icon: Icons.tag_outlined,
              ),
              _infoRow(
                'Phone',
                farmer.phoneNumber,
                icon: Icons.phone_outlined,
              ),
              _infoRow('Email', farmer.email, icon: Icons.email_outlined),
              _infoRow('Gender', farmer.gender, icon: Icons.wc_outlined),
              _infoRow(
                'Nationality',
                farmer.nationality,
                icon: Icons.flag_outlined,
              ),
              _infoRow(
                'Enumerator',
                farmer.enumeratorName,
                icon: Icons.person_pin_outlined,
              ),
              _infoRow(
                'Registered',
                farmer.createdAt?.toLocal().toString().split('.').first,
                icon: Icons.event_outlined,
              ),
            ],
          ),
          _sectionCard(
            title: 'Location',
            icon: Icons.location_on_outlined,
            children: [
              _infoRow('Community', farmer.community),
              _infoRow('District', farmer.district),
              _infoRow('Region', farmer.region),
              _infoRow('Address', farmer.address),
            ],
          ),
          if (farmer.farms.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: AppTheme.border),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppTheme.paleGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.grass,
                        size: 36,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No farm details recorded',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _addFarm,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Add Farm'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...farmer.farms.asMap().entries.map((entry) {
              final i = entry.key;
              final farm = entry.value;
              return _sectionCard(
                title: 'Farm ${i + 1}: ${farm.name}',
                icon: Icons.grass_outlined,
                children: [
                  Row(
                    children: [
                      StatusBadge(label: farm.geometryStatus.label),
                      if (farm.overlapsExistingFarm) ...[
                        const SizedBox(width: 8),
                        const StatusBadge(label: 'Overlap Detected'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _infoRow('Crop Type', farm.cropType),
                  _infoRow('Risk Level', farm.riskLevel),
                  _infoRow(
                    'Area',
                    farm.totalAreaHa != null ? '${farm.totalAreaHa} ha' : null,
                  ),
                  _infoRow(
                    'Calculated Area',
                    farm.calculatedAreaHa != null
                        ? '${farm.calculatedAreaHa!.toStringAsFixed(2)} ha'
                        : null,
                  ),
                  _infoRow(
                    'Area Difference',
                    farm.areaDifferencePercent != null
                        ? '${farm.areaDifferencePercent!.toStringAsFixed(1)}%'
                        : null,
                  ),
                  _infoRow(
                    'GPS Accuracy',
                    farm.gpsAccuracyM != null
                        ? '${farm.gpsAccuracyM!.toStringAsFixed(1)} m'
                        : null,
                  ),
                  _infoRow('Ownership', farm.ownershipType),
                  _infoRow('Registration', farm.farmRegistrationStatus),
                  _infoRow('Notes', farm.farmNotes),
                  if (farm.needsAttention &&
                      (farm.geometryWarnings.isNotEmpty ||
                          farm.geometryErrors.isNotEmpty))
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: farm.geometryErrors.isNotEmpty
                            ? AppTheme.dangerBg
                            : AppTheme.warningBg,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMd,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...farm.geometryErrors.map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
