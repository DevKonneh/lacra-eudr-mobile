import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../config/feature_access.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../routes/app_routes.dart';
import '../theme/app_theme.dart';
import 'farmer_registry_screen.dart';
import 'farmers_list_screen.dart';
import 'create_inspector_screen.dart';
import 'profile_screen.dart';

/// Live, public License & Permit Application form - the exact same page
/// served at https://lacra-admin.onrender.com/apply, embedded in-app via
/// WebView so there is a single source of truth for the form (no separate
/// native re-implementation to keep in sync).
const String _licenseApplyUrl = 'https://lacra-admin.onrender.com/apply';

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
  bool _canAccessLicenseApply = false;
  User? _currentUser;

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
        _currentUser = user;
        _isAdmin = user.role.toUpperCase() == 'ADMIN';
        _canAccessLicenseApply = FeatureAccess.canAccessLicenseApply(
          user.email,
        );
      });
    }
  }

  void _openLicenseApply() {
    Navigator.of(context).pushNamed(
      AppRoutes.webview,
      arguments: {
        'url': _licenseApplyUrl,
        'title': 'License & Permit Application',
      },
    );
  }

  String _userInitial() {
    final name = _currentUser?.name.trim() ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    // Refresh in case the name/role could have changed (e.g. after a
    // future profile-edit feature); harmless no-op today.
    _loadUserRole();
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

  Widget _scannerActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: const Column(
              children: [
                Icon(Icons.qr_code_scanner, size: 64, color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'QR Scanner',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Scan QR codes to view farmer or batch details',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _scannerActionCard(
            icon: Icons.people_outline,
            title: 'Scan Farmer QR',
            subtitle: 'View a farmer\'s registered profile and farms',
            accent: AppTheme.primaryGreen,
            onTap: () {
              Navigator.of(
                context,
              ).pushNamed(AppRoutes.qrScanner, arguments: 'farmer');
            },
          ),
          const SizedBox(height: 14),
          _scannerActionCard(
            icon: Icons.inventory_2_outlined,
            title: 'Scan Batch QR',
            subtitle: 'View traceability details for a commodity batch',
            accent: AppTheme.info,
            onTap: () {
              Navigator.of(
                context,
              ).pushNamed(AppRoutes.qrScanner, arguments: 'batch');
            },
          ),
          // Pilot feature: restricted to a single test account for now
          // (see FeatureAccess.licenseApplyTestEmails) - does not affect
          // farm data collection for any other user.
          if (_canAccessLicenseApply) ...[
            const SizedBox(height: 14),
            _scannerActionCard(
              icon: Icons.fact_check_outlined,
              title: 'License & Permit Application',
              subtitle: 'Apply for or verify a License/Permit (pilot)',
              accent: AppTheme.warning,
              onTap: _openLicenseApply,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: _openProfile,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  _userInitial(),
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('LACRA Dashboard', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        centerTitle: false,
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
