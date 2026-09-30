import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/geoid_farm_qr_widget.dart';

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

  Widget _infoRow(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF757575),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF388E3C),
              ),
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Verified':
        return Colors.green;
      case 'Conflict':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color _riskColor(String? risk) {
    switch (risk) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      default:
        return const Color(0xFF4CAF50);
    }
  }

  Widget _buildRiskRow(String? riskLevel) {
    if (riskLevel == null || riskLevel.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Text(
              'Risk Level',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF757575),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _riskColor(riskLevel).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _riskColor(riskLevel).withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              riskLevel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _riskColor(riskLevel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_farmer?.fullName ?? 'Farmer Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575)),
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
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFF4CAF50).withValues(
                    alpha: 0.15,
                  ),
                  child: Text(
                    farmer.fullName.isNotEmpty
                        ? farmer.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF388E3C),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  farmer.fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(
                      farmer.identityStatus,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    farmer.identityStatus,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _statusColor(farmer.identityStatus),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Farmer QR code (links to public farmer profile)
          if (farmer.qrCode != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _copyToClipboard(
                'https://lacra-eudr-backend.onrender.com/api/public/farmers/${farmer.id}',
                'Farmer profile link',
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code,
                      size: 14,
                      color: Color(0xFF757575),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Farmer QR — tap to copy profile link',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _sectionCard(
            title: 'Personal Information',
            children: [
              _infoRow('Farmer ID', farmer.farmerId),
              _infoRow('Phone', farmer.phoneNumber),
              _infoRow('Email', farmer.email),
              _infoRow('Gender', farmer.gender),
              _infoRow('Nationality', farmer.nationality),
              _infoRow('Enumerator', farmer.enumeratorName),
              _infoRow(
                'Registered',
                farmer.createdAt?.toLocal().toString().split('.').first,
              ),
            ],
          ),
          _sectionCard(
            title: 'Location',
            children: [
              _infoRow('Community', farmer.community),
              _infoRow('District', farmer.district),
              _infoRow('Region', farmer.region),
              _infoRow('Address', farmer.address),
            ],
          ),
          if (farmer.farms.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.grass, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('No farm details recorded'),
                    ],
                  ),
                ),
              ),
            )
          else
            ...farmer.farms.asMap().entries.map((entry) {
              final i = entry.key;
              final farm = entry.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionCard(
                    title: 'Farm ${i + 1}: ${farm.name}',
                    children: [
                      _infoRow('Crop Type', farm.cropType),
                      _buildRiskRow(farm.riskLevel),
                      _infoRow(
                        'Area',
                        farm.totalAreaHa != null
                            ? '${farm.totalAreaHa} ha'
                            : null,
                      ),
                      _infoRow('Ownership', farm.ownershipType),
                      _infoRow('Registration', farm.farmRegistrationStatus),
                      _infoRow('Notes', farm.farmNotes),
                    ],
                  ),
                  // GeoID + Farm QR section
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GeoIdFarmQrWidget(
                      farmId: farm.id,
                      geoId: farm.geoId,
                      geoIdUri: farm.geoIdUri,
                      farmQrCode: farm.farmQrCode,
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
