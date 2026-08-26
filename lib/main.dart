import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'routes/app_routes.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/webview_screen.dart';
import 'screens/pending_sync_screen.dart';
import 'screens/create_inspector_screen.dart';
import 'screens/drafts_list_screen.dart';
import 'screens/offline_submissions_screen.dart';

void main() {
  runApp(const InspectorApp());
}

class InspectorApp extends StatelessWidget {
  const InspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LACRA Farm Mapping Tools',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppRoutes.login:
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case AppRoutes.forgotPassword:
            return MaterialPageRoute(
              builder: (_) => const ForgotPasswordScreen(),
            );
          case AppRoutes.resetPassword:
            return MaterialPageRoute(
              builder: (_) =>
                  ResetPasswordScreen(email: settings.arguments as String?),
            );
          case AppRoutes.dashboard:
            return MaterialPageRoute(builder: (_) => const DashboardScreen());
          case AppRoutes.qrScanner:
            return MaterialPageRoute(
              builder: (_) => const QRScannerScreen(),
              settings: settings,
            );
          case AppRoutes.webview:
            return MaterialPageRoute(
              builder: (_) => const WebViewScreen(),
              settings: settings,
            );
          case AppRoutes.pendingSync:
            return MaterialPageRoute(builder: (_) => const PendingSyncScreen());
          case AppRoutes.createInspector:
            return MaterialPageRoute(
              builder: (_) => const CreateInspectorScreen(),
            );
          case AppRoutes.drafts:
            return MaterialPageRoute(builder: (_) => const DraftsListScreen());
          case AppRoutes.offlineSubmissions:
            return MaterialPageRoute(
              builder: (_) => const OfflineSubmissionsScreen(),
            );
          default:
            return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  Future<void> _checkAuth() async {
    _debugLog('🔐 Checking authentication status...');
    final isAuth = await _authService.isAuthenticated();

    if (isAuth) {
      _debugLog('✅ User is authenticated');
    } else {
      _debugLog('❌ User is not authenticated - showing login screen');
    }

    setState(() {
      _isAuthenticated = isAuth;
      _isLoading = false;
    });

    if (mounted) {
      if (_isAuthenticated) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
          ),
        ),
      );
    }

    return _isAuthenticated ? const DashboardScreen() : const LoginScreen();
  }
}
