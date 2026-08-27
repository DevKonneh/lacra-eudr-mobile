import 'package:flutter/material.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/snapping_list_view.dart';
import '../widgets/status_badge.dart';
import 'farmer_detail_screen.dart';

/// Fixed row height used for the snap-to-item list below. Every farmer
/// card must fit within this height for the snapping math to line up.
const double _kFarmerCardExtent = 126;

/// Shows every farmer that has actually been submitted to the server so
/// far (via GET /api/farmers). This is the missing "where do I see the
/// data I just entered" screen - registration alone only shows a one-off
/// success snackbar and drops the inspector back at the dashboard.
class FarmersListScreen extends StatefulWidget {
  const FarmersListScreen({super.key});

  @override
  State<FarmersListScreen> createState() => _FarmersListScreenState();
}

class _FarmersListScreenState extends State<FarmersListScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<FarmerRecord> _farmers = [];
  List<FarmerRecord> _filtered = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-load as soon as this screen appears, don't wait for a manual
    // pull-to-refresh - that's the #1 cause of "no data found" confusion.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFarmers());
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFarmers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _authService.getToken();
      final farmers = await _apiService.getFarmers(authToken: token);

      // Sort newest-first in memory (avoids needing a backend index/orderBy).
      farmers.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _farmers = farmers;
        _isLoading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = _farmers;
      } else {
        _filtered = _farmers.where((f) {
          return f.fullName.toLowerCase().contains(query) ||
              (f.community ?? '').toLowerCase().contains(query) ||
              (f.district ?? '').toLowerCase().contains(query) ||
              (f.phoneNumber).toLowerCase().contains(query) ||
              (f.farmerId ?? '').toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, community, phone...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryGreen,
                    width: 1.8,
                  ),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          if (!_isLoading && _error == null && _farmers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_filtered.length} of ${_farmers.length} farmer(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
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
                decoration: BoxDecoration(
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
              const Text(
                'Could not load farmers',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadFarmers,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filtered.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.primaryGreen,
        onRefresh: _loadFarmers,
        child: ListView(
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppTheme.paleGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _farmers.isEmpty
                            ? Icons.people_outline
                            : Icons.search_off,
                        size: 44,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _farmers.isEmpty
                          ? 'No farmers registered yet'
                          : 'No matches found',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pull down to refresh',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SnappingListView<FarmerRecord>(
      items: _filtered,
      itemExtent: _kFarmerCardExtent,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      onRefresh: _loadFarmers,
      keyOf: (farmer) => farmer.id,
      itemBuilder: (context, farmer, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FarmerDetailScreen(farmerId: farmer.id),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.paleGreen,
                      child: Text(
                        farmer.fullName.isNotEmpty
                            ? farmer.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppTheme.darkGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  farmer.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusBadge(label: farmer.identityStatus),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if ([
                            farmer.community,
                            farmer.district,
                          ].any((s) => (s ?? '').isNotEmpty))
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 13,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    [
                                      farmer.community,
                                      farmer.district,
                                    ].where((s) => (s ?? '').isNotEmpty).join(
                                      ', ',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (farmer.farms.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.grass_outlined,
                                  size: 13,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${farmer.farms.length} farm(s) · '
                                  '${farmer.farms.first.cropType ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
