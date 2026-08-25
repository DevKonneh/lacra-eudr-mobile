import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/login_response_model.dart';
import '../models/farmer_registration_model.dart';

class ApiService {
  // LACRA EUDR backend, deployed on Render.com (Docker web service + managed
  // Postgres). Used by both native Android/iOS builds and the Flutter Web
  // preview — the backend's CORS config (see src/index.ts on the server)
  // explicitly allows any *.onrender.com origin plus a configurable list of
  // extra origins via the CORS_EXTRA_ORIGINS env var, so a single base URL
  // works for every platform without needing a separate web-preview URL.
  static const String _productionBaseUrl =
      'https://lacra-eudr-backend.onrender.com/api';

  static const String baseUrl = _productionBaseUrl;

  /// Debug-only logger. Never prints in release builds and never logs
  /// sensitive values like the Authorization header or password fields.
  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  Future<LoginResponse> inspectorLogin({
    required String email,
    required String password,
  }) async {
    try {
      final url = '$baseUrl/auth/login';
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'email': email, 'password': password});

      _log('API REQUEST - Inspector Login: POST $url (email: $email)');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      _log('API RESPONSE - Inspector Login: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final loginResponse = LoginResponse.fromJson(jsonData);

        // Check if login was successful
        if (!loginResponse.status) {
          final errorMessage = loginResponse.errors.isNotEmpty
              ? loginResponse.errors.join(', ')
              : (loginResponse.message ?? 'Login failed');
          throw Exception(errorMessage);
        }

        return loginResponse;
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final errors = errorData['errors'] != null
            ? List<String>.from(errorData['errors'] as List)
            : [];
        final message = errorData['message'] as String?;
        throw Exception(
          errors.isNotEmpty ? errors.join(', ') : (message ?? 'Login failed'),
        );
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> registerFarmer({
    required FarmerRegistrationModel farmerData,
    required String? authToken,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/register-farmer'),
      );

      // Add headers
      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      // Add JSON fields
      final jsonData = farmerData.toJson();
      jsonData.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      // Add files
      final List<String> fileNames = [];
      if (farmerData.farmerPhotoPath != null) {
        final file = File(farmerData.farmerPhotoPath!);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'farmerPhoto',
              farmerData.farmerPhotoPath!,
              filename: 'farmer_photo.jpg',
            ),
          );
          fileNames.add('farmerPhoto: ${file.path}');
        }
      }

      if (farmerData.nationalIdPath != null) {
        final file = File(farmerData.nationalIdPath!);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'nationalId',
              farmerData.nationalIdPath!,
            ),
          );
          fileNames.add('nationalId: ${file.path}');
        }
      }

      if (farmerData.farmSelfiePath != null) {
        final file = File(farmerData.farmSelfiePath!);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'farmSelfie',
              farmerData.farmSelfiePath!,
              filename: 'farm_selfie.jpg',
            ),
          );
          fileNames.add('farmSelfie: ${file.path}');
        }
      }

      if (farmerData.farmPhotosPaths != null) {
        for (int i = 0; i < farmerData.farmPhotosPaths!.length; i++) {
          final file = File(farmerData.farmPhotosPaths![i]);
          if (await file.exists()) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'farmPhotos',
                farmerData.farmPhotosPaths![i],
                filename: 'farm_photo_$i.jpg',
              ),
            );
            fileNames.add('farmPhotos[$i]: ${file.path}');
          }
        }
      }

      _log(
        'API REQUEST - Register Farmer: POST ${request.url} '
        '(${request.fields.length} fields, ${fileNames.length} files)',
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _log('API RESPONSE - Register Farmer: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        return jsonData;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Farmer registration failed');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Calls POST /auth/forget-password with {email}.
  /// Backend always returns success (even if the account doesn't exist)
  /// to prevent user enumeration, so this only throws on network/server errors.
  Future<void> forgotPassword({required String email}) async {
    try {
      final url = '$baseUrl/auth/forget-password';
      _log('API REQUEST - Forgot Password: POST $url (email: $email)');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      _log('API RESPONSE - Forgot Password: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to send verification code'),
        );
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Calls POST /auth/reset-password with {email, verificationCode, newPassword}.
  Future<void> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    try {
      final url = '$baseUrl/auth/reset-password';
      _log('API REQUEST - Reset Password: POST $url (email: $email)');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'verificationCode': verificationCode,
          'newPassword': newPassword,
        }),
      );

      _log('API RESPONSE - Reset Password: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to reset password'),
        );
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Calls POST /farmer/offline-sync with {farmer, farms}. Used by
  /// OfflineSyncService to flush queued farmer registrations that were
  /// captured while offline (or that failed the live multipart submission
  /// due to a network error). Note this endpoint accepts plain JSON only -
  /// photos captured offline are not uploaded through this path.
  Future<Map<String, dynamic>> syncFarmerOffline({
    required Map<String, dynamic> farmer,
    required List<Map<String, dynamic>> farms,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/farmers/offline-sync';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log(
        'API REQUEST - Offline Sync Farmer: POST $url '
        '(${farms.length} farm(s) attached)',
      );

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({'farmer': farmer, 'farms': farms}),
      );

      _log('API RESPONSE - Offline Sync Farmer: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonData;
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to sync farmer'),
        );
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: ${e.toString()}');
    }
  }
}
