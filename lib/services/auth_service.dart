import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/login_response_model.dart';
import 'api_service.dart';

class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  Future<LoginResponse> login(String email, String password) async {
    final response = await _apiService.inspectorLogin(
      email: email,
      password: password,
    );

    // Store token and user data in secure storage
    await _storage.write(key: _tokenKey, value: response.token);
    await _storage.write(
      key: _userKey,
      value: jsonEncode(response.user.toJson()),
    );

    _log('💾 Session stored in secure storage');

    return response;
  }

  /// Requests a 6-digit password reset code to be emailed to [email].
  Future<void> forgotPassword(String email) {
    return _apiService.forgotPassword(email: email);
  }

  /// Resets the password using the code emailed via [forgotPassword].
  Future<void> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) {
    return _apiService.resetPassword(
      email: email,
      verificationCode: verificationCode,
      newPassword: newPassword,
    );
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<User?> getUser() async {
    final userJsonString = await _storage.read(key: _userKey);
    if (userJsonString == null) return null;
    try {
      final userJson = jsonDecode(userJsonString) as Map<String, dynamic>;
      return User.fromJson(userJson);
    } catch (e) {
      // Fallback to old format for backward compatibility
      return _userFromJsonString(userJsonString);
    }
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    final hasToken = token != null && token.isNotEmpty;

    if (hasToken) {
      _log('🔑 Valid session found in secure storage');
    } else {
      _log('🔓 No session found in secure storage');
    }

    return hasToken;
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    _log('🗑️ Session data deleted from secure storage');
  }

  String _userToJsonString(User user) {
    return '${user.id}|${user.email}|${user.role}|${user.name}';
  }

  User _userFromJsonString(String jsonString) {
    final parts = jsonString.split('|');
    return User(id: parts[0], email: parts[1], role: parts[2], name: parts[3]);
  }
}
