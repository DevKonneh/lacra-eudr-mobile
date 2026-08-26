import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../services/auth_service.dart';
import '../routes/app_routes.dart';
import 'farmer_registry_screen.dart';
import 'farmers_list_screen.dart';
import 'create_inspector_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = await _authService.getUser();
    if (mounted && user != null) {
      setState(() {
        _isAdmin = user.role.toUpperCase() == 'ADMIN';
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (kDebugMode) {
        // ignore: avoid_print
        print('🚪 User logged out - Session cleared from secure storage');
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    }
  }

  Widget _buildScannerTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.qr_code_scanner,
              size: 80,
              color: Color(0xFF4CAF50),
            ),
            const SizedBox(height: 24),
            const Text(
              'QR Scanner',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan QR codes to view farmer or batch details',
              style: TextStyle(fontSize: 16, color: Color(0xFF757575)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.qrScanner, arguments: 'farmer');
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Scan Farmer QR'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.qrScanner, arguments: 'batch');
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Scan Batch QR'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LACRA Dashboard'),
        actions: [
          // Admin-only: create new Inspector accounts from the field, since
          // multiple people use this app and admins need a quick way to
          // provision logins without the web admin panel.
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateInspectorScreen(),
                  ),
                );
              },
              tooltip: 'Create Inspector',
            ),
          IconButton(
            icon: const Icon(Icons.drafts_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.drafts);
            },
            tooltip: 'Drafts',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.pendingSync);
            },
            tooltip: 'Pending Sync',
          ),
          // Visible to Admin + Inspector (matches backend role gating on
          // GET /offline-submissions): team-wide visibility into farmer
          // registrations captured in the field on ANY device that
          // haven't fully synced yet - not just this device's own queue.
          IconButton(
            icon: const Icon(Icons.cloud_off_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.offlineSubmissions);
            },
            tooltip: 'Unsynced Field Data',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner'),
            Tab(icon: Icon(Icons.person_add), text: 'Register'),
            Tab(icon: Icon(Icons.people_outline), text: 'Farmers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Scanner Tab - QR Scanner functionality
          _buildScannerTab(),
          // Farmer Registry Tab
          const FarmerRegistryScreen(),
          // Farmers List Tab - view everything submitted so far
          const FarmersListScreen(),
        ],
      ),
    );
  }
}
