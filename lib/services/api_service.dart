import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../models/login_response_model.dart';
import '../models/farmer_registration_model.dart';

class ApiService {
  // Production API used by native Android/iOS builds (not subject to browser CORS).
  static const String _productionBaseUrl = 'https://eudr-api.netdivs.us/api';

  // Public sandbox URL for the local backend, used only for the Flutter Web preview.
  // Browser CORS policy blocks the production API from the sandbox preview origin,
  // and "localhost" in browser JS would resolve to the viewer's own machine, not the
  // sandbox host — so Web builds must talk to this publicly reachable backend URL.
  static const String _webPreviewBaseUrl =
      'https://8100-i9tadgf8ntmirkrse9hvt-de59bda9.sandbox.novita.ai/api';

  static const String baseUrl = kIsWeb ? _webPreviewBaseUrl : _productionBaseUrl;
  static const String localBaseUrl = 'http://localhost:3000/api';
  
  Future<LoginResponse> inspectorLogin({
    required String email,
    required String password,
  }) async {
    try {
      final url = '$baseUrl/auth/login';
      final headers = {
        'Content-Type': 'application/json',
      };
      final body = jsonEncode({
        'email': email,
        'password': password,
      });

      // Prepare complete request data for JSON printing
      final requestData = {
        'url': url,
        'method': 'POST',
        'headers': headers,
        'body': jsonDecode(body),
      };

      // Print API details
      print('========================================');
      print('API REQUEST - Inspector Login');
      print('========================================');
      print('Complete Request (JSON):');
      print(const JsonEncoder.withIndent('  ').convert(requestData));
      print('========================================');
      
      // Also print in detailed format
      print('Detailed Request:');
      print('URL: $url');
      print('Method: POST');
      print('Headers:');
      headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('Body:');
      print('  ${const JsonEncoder.withIndent('  ').convert(jsonDecode(body))}');
      print('========================================');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      // Print response details
      print('========================================');
      print('API RESPONSE - Inspector Login');
      print('========================================');
      print('Status Code: ${response.statusCode}');
      print('Response Headers:');
      response.headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('Response Body:');
      try {
        final responseJson = jsonDecode(response.body);
        print('  ${const JsonEncoder.withIndent('  ').convert(responseJson)}');
      } catch (e) {
        print('  ${response.body}');
      }
      print('========================================');

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
          errors.isNotEmpty
              ? errors.join(', ')
              : (message ?? 'Login failed'),
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

      // Prepare complete request data for JSON printing
      final requestData = {
        'url': request.url.toString(),
        'method': request.method,
        'headers': request.headers,
        'fields': request.fields,
        'files': fileNames.isEmpty 
            ? [] 
            : fileNames.map((name) => {'name': name.split(': ')[0], 'path': name.split(': ').length > 1 ? name.split(': ')[1] : ''}).toList(),
      };

      // Print API details
      print('========================================');
      print('API REQUEST - Register Farmer');
      print('========================================');
      print('Complete Request (JSON):');
      print(const JsonEncoder.withIndent('  ').convert(requestData));
      print('========================================');
      
      // Also print in detailed format
      print('Detailed Request:');
      print('URL: ${request.url}');
      print('Method: ${request.method}');
      print('Headers:');
      request.headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('Fields:');
      request.fields.forEach((key, value) {
        print('  $key: $value');
      });
      print('Files:');
      if (fileNames.isEmpty) {
        print('  (none)');
      } else {
        for (var fileName in fileNames) {
          print('  $fileName');
        }
      }
      print('========================================');

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Print response details
      print('========================================');
      print('API RESPONSE - Register Farmer');
      print('========================================');
      print('Status Code: ${response.statusCode}');
      print('Response Headers:');
      response.headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('Response Body:');
      try {
        final responseJson = jsonDecode(response.body);
        print('  ${const JsonEncoder.withIndent('  ').convert(responseJson)}');
      } catch (e) {
        print('  ${response.body}');
      }
      print('========================================');

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
}
