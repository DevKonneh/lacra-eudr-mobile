import 'package:flutter/material.dart';
import '../models/farmer_record_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/snapping_list_view.dart';
import 'farmer_detail_screen.dart';

/// Fixed row height used for the snap-to-item list below. Every farmer
/// card must fit within this height for the snapping math to line up.
const double _kFarmerCardExtent = 118;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, community, phone...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
              const Text(
                'Could not load farmers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575)),
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
        onRefresh: _loadFarmers,
        child: ListView(
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _farmers.isEmpty
                          ? Icons.people_outline
                          : Icons.search_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _farmers.isEmpty
                          ? 'No farmers registered yet'
                          : 'No matches found',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pull down to refresh',
                      style: TextStyle(color: Color(0xFF757575)),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      onRefresh: _loadFarmers,
      keyOf: (farmer) => farmer.id,
      itemBuilder: (context, farmer, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(
                  0xFF4CAF50,
                ).withValues(alpha: 0.15),
                child: Text(
                  farmer.fullName.isNotEmpty
                      ? farmer.fullName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Color(0xFF388E3C),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                farmer.fullName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    [
                      farmer.community,
                      farmer.district,
                    ].where((s) => (s ?? '').isNotEmpty).join(', '),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (farmer.farms.isNotEmpty)
                    Text(
                      '${farmer.farms.length} farm(s) · '
                      '${farmer.farms.first.cropType ?? '-'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                      ),
                    ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(
                    farmer.identityStatus,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  farmer.identityStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(farmer.identityStatus),
                  ),
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FarmerDetailScreen(farmerId: farmer.id),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
