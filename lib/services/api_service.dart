import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/login_response_model.dart';
import '../models/farmer_registration_model.dart';
import '../models/farmer_record_model.dart';

class ApiService {
  // Some networks (certain mobile carriers, restrictive Wi-Fi/firewalls)
  // cannot reach Render's Cloudflare-fronted edge at all - the OS-level
  // socket timeout for that can take 60-120+ seconds before surfacing an
  // error, leaving the inspector staring at a frozen "Login"/"Submit"
  // button in the field. These explicit, shorter timeouts fail fast with
  // a clear, actionable message instead.
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _uploadTimeout = Duration(seconds: 60);

  static const String _networkUnreachableMessage =
      'Can\'t reach the server. This can happen on some mobile networks or '
      'Wi-Fi that block the connection. Please try switching networks '
      '(e.g. Wi-Fi \u2194 mobile data) and try again.';

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

      final response = await http
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(_requestTimeout);

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
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
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

      if (farmerData.signaturePath != null) {
        final file = File(farmerData.signaturePath!);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'signature',
              farmerData.signaturePath!,
              filename: 'signature.jpg',
            ),
          );
          fileNames.add('signature: ${file.path}');
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

      // Send request (uploads can take longer than a plain JSON call since
      // they include photos/signature - use the longer upload timeout).
      final streamedResponse = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      _log('API RESPONSE - Register Farmer: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        return jsonData;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Farmer registration failed');
      }
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
    }
  }

  /// Attaches EUDR-standard boundary evidence (per-point geotagged photos,
  /// minimum 4 points) to an already-created farm via
  /// PUT /farms/:id/boundary-evidence. Called as a follow-up right after
  /// [registerFarmer] succeeds and returns the new farm's id - kept as a
  /// separate call so the point/photo-matching logic lives only on the
  /// backend's FarmController.addBoundaryEvidence, not duplicated here.
  ///
  /// [points] - list of {sequence, lat, lng, accuracy, timestamp, photoPath}
  /// as produced by FarmMapWidget's Point + Photo mode. photoPath is a
  /// local file path; it is uploaded as field `boundaryPhoto_<sequence>`.
  Future<Map<String, dynamic>> addBoundaryEvidence({
    required String farmId,
    required List<Map<String, dynamic>> points,
    required String? authToken,
  }) async {
    try {
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/farms/$farmId/boundary-evidence'),
      );

      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      // Metadata only (no photoPath - that goes as a file below).
      final pointsMeta = points
          .map(
            (p) => {
              'sequence': p['sequence'],
              'lat': p['lat'],
              'lng': p['lng'],
              if (p['accuracy'] != null) 'accuracy': p['accuracy'],
              if (p['timestamp'] != null) 'timestamp': p['timestamp'],
            },
          )
          .toList();
      request.fields['points'] = jsonEncode(pointsMeta);

      int filesAdded = 0;
      for (final p in points) {
        final path = p['photoPath'] as String?;
        final sequence = p['sequence'];
        if (path == null) continue;
        final file = File(path);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'boundaryPhoto_$sequence',
              path,
              filename: 'boundary_point_$sequence.jpg',
            ),
          );
          filesAdded++;
        }
      }

      _log(
        'API REQUEST - Add Boundary Evidence: PUT ${request.url} '
        '(${pointsMeta.length} points, $filesAdded photos)',
      );

      final streamedResponse = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      _log('API RESPONSE - Add Boundary Evidence: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ?? 'Failed to save boundary evidence',
        );
      }
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
    }
  }

  /// Calls POST /auth/forget-password with {email}.
  /// Backend always returns success (even if the account doesn't exist)
  /// to prevent user enumeration, so this only throws on network/server errors.
  Future<void> forgotPassword({required String email}) async {
    try {
      final url = '$baseUrl/auth/forget-password';
      _log('API REQUEST - Forgot Password: POST $url (email: $email)');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(_requestTimeout);

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
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
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

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'verificationCode': verificationCode,
              'newPassword': newPassword,
            }),
          )
          .timeout(_requestTimeout);

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
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
    }
  }

  /// Calls GET /farmers to fetch every farmer registered so far (with their
  /// farms). Used by FarmersListScreen so inspectors can review what has
  /// actually been submitted to the server - not just what's queued locally.
  Future<List<FarmerRecord>> getFarmers({required String? authToken}) async {
    try {
      final url = '$baseUrl/farmers';
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Get Farmers: GET $url');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Get Farmers: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final list = jsonData['data'];
        if (list is! List) return [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(FarmerRecord.fromJson)
            .toList();
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to load farmers'),
        );
      }
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
    }
  }

  /// Calls GET /farmers/:id to fetch full detail (including farms) for a
  /// single farmer. Used by FarmerDetailScreen.
  Future<FarmerRecord> getFarmer({
    required String id,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/farmers/$id';
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Get Farmer: GET $url');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Get Farmer: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return FarmerRecord.fromJson(jsonData['data'] as Map<String, dynamic>);
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to load farmer'),
        );
      }
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
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

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({'farmer': farmer, 'farms': farms}),
          )
          .timeout(_requestTimeout);

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
    } on TimeoutException {
      throw Exception(_networkUnreachableMessage);
    } on SocketException {
      throw Exception(_networkUnreachableMessage);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(_networkUnreachableMessage);
    }
  }
}
