import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/login_response_model.dart';
import 'api_service.dart';

class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

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
    
    print('💾 Session stored in secure storage');
    print('   Token key: $_tokenKey');
    print('   User key: $_userKey');
    
    return response;
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
      print('🔑 Valid session found in secure storage');
    } else {
      print('🔓 No session found in secure storage');
    }
    
    return hasToken;
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    print('🗑️ Session data deleted from secure storage');
  }

  String _userToJsonString(User user) {
    return '${user.id}|${user.email}|${user.role}|${user.name}';
  }

  User _userFromJsonString(String jsonString) {
    final parts = jsonString.split('|');
    return User(
      id: parts[0],
      email: parts[1],
      role: parts[2],
      name: parts[3],
    );
  }
}
