import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/login_response_model.dart';
import '../models/farmer_registration_model.dart';
import '../models/farmer_record_model.dart';
import '../models/offline_submission_record.dart';
import '../data/cda_cooperatives.dart';

class ApiService {
  // Some networks (certain mobile carriers, restrictive Wi-Fi/firewalls)
  // cannot reach Render's Cloudflare-fronted edge at all - the OS-level
  // socket timeout for that can take 60-120+ seconds before surfacing an
  // error, leaving the inspector staring at a frozen "Login"/"Submit"
  // button in the field. These explicit, shorter timeouts fail fast with
  // a clear, actionable message instead.
  static const Duration _requestTimeout = Duration(seconds: 20);
  // Farmer registrations can include several photos plus compliance
  // document scans (PDFs), sometimes uploaded over weak field connections.
  // 60s was too aggressive - it was cutting off uploads that were still
  // actively transferring (confirmed in production: the farmer record was
  // created successfully server-side seconds after the client had already
  // given up and marked the item FAILED). 180s gives slow/rural connections
  // a realistic chance to finish before we time out.
  static const Duration _uploadTimeout = Duration(seconds: 180);

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

  /// Returns the file extension (including the leading dot) from [path],
  /// or '.jpg' if none is present - used so compliance documents keep their
  /// original type (e.g. PDFs) instead of always being renamed to .jpg.
  String _extensionOf(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) return '.jpg';
    return path.substring(lastDot);
  }

  Future<Map<String, dynamic>> registerFarmer({
    required FarmerRegistrationModel farmerData,
    required String? authToken,
    // Stable local record id (PendingSyncItem.id) used ONLY when this
    // submission is being replayed from the offline-sync queue - lets the
    // backend detect/reject an accidental duplicate create if the SAME
    // queued record is ever submitted twice (e.g. a retry after a
    // response was lost mid-flight even though the first attempt actually
    // succeeded server-side). Omitted entirely for a normal live/online
    // submission, since there is no queue item to dedup against.
    String? clientRecordId,
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
      if (clientRecordId != null) {
        request.fields['clientRecordId'] = clientRecordId;
      }

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

      // EUDR compliance documents (National ID, Land Deed, Lease Agreement,
      // Customary/Community Authorization, Cooperative Membership Document).
      // Sent as multiple 'complianceDocuments' files, with a parallel JSON
      // array of their types (same order) so the backend can tag each one
      // correctly - see AuthController.registerFarmer's handling of
      // 'complianceDocTypes'.
      if (farmerData.complianceDocuments != null &&
          farmerData.complianceDocuments!.isNotEmpty) {
        final docTypes = <String>[];
        for (int i = 0; i < farmerData.complianceDocuments!.length; i++) {
          final doc = farmerData.complianceDocuments![i];
          final path = doc['path'];
          final type = doc['type'];
          if (path == null || type == null) continue;
          final file = File(path);
          if (await file.exists()) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'complianceDocuments',
                path,
                filename: 'compliance_doc_$i${_extensionOf(path)}',
              ),
            );
            docTypes.add(type);
            fileNames.add('complianceDocuments[$i] ($type): $path');
          }
        }
        if (docTypes.isNotEmpty) {
          request.fields['complianceDocTypes'] = jsonEncode(docTypes);
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
  ///
  /// [location] - optional GeoJSON Polygon/Feature geometry (as produced by
  /// FarmMapWidget's `onBoundaryDrawn`/pop result) to REPLACE the farm's
  /// stored boundary in the same request. Used by EditBoundaryScreen when
  /// re-walking an EXISTING farm's perimeter - the backend
  /// (FarmController.addBoundaryEvidence) re-runs GPS polygon/area geometry
  /// validation and re-mints the farm's GeoID whenever `location` is
  /// present, and returns the updated farm (with fresh geometryStatus,
  /// calculatedAreaHa, etc.) in the response - see EditBoundaryScreen for
  /// how that result is parsed and surfaced to the user. When omitted
  /// (e.g. the brand-new-farmer registration flow), only the per-point
  /// evidence is attached and the farm's existing `location` is untouched.
  ///
  /// [totalAreaHa] - optional declared area (hectares) to update alongside
  /// a new [location], so the backend's area-mismatch check compares the
  /// freshly re-walked polygon against an up-to-date declared figure
  /// rather than a stale one from the farm's original registration.
  Future<Map<String, dynamic>> addBoundaryEvidence({
    required String farmId,
    required List<Map<String, dynamic>> points,
    required String? authToken,
    Map<String, dynamic>? location,
    double? totalAreaHa,
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

      if (location != null) {
        final geometry = location['geometry'] ?? location;
        request.fields['location'] = jsonEncode(geometry);
      }
      if (totalAreaHa != null) {
        request.fields['totalAreaHa'] = totalAreaHa.toString();
      }

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

  /// Calls POST /users (admin-only on the backend) to create a new INSPECTOR
  /// account. Used by CreateInspectorScreen - only ADMIN accounts can reach
  /// that screen, and the backend independently enforces the same
  /// restriction via authMiddleware([UserRole.ADMIN]) on /api/users.
  Future<void> createInspector({
    required String name,
    required String email,
    required String password,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/users';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }
      final body = jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'roleType': 'INSPECTOR',
      });

      _log('API REQUEST - Create Inspector: POST $url (email: $email)');

      final response = await http
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Create Inspector: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 && response.statusCode != 201) {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to create inspector account'),
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

  /// Calls POST /auth/change-password with {currentPassword, newPassword}.
  /// Used by the in-app Profile screen so a logged-in user can update their
  /// own password (server verifies currentPassword before accepting the
  /// change) - distinct from forgotPassword/resetPassword's email-code flow
  /// for users who are locked out.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/auth/change-password';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Change Password: POST $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(_requestTimeout);

      _log('API RESPONSE - Change Password: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to update password'),
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

  /// Calls GET /cooperatives to fetch the real CDA (Cooperative Development
  /// Agency) registry - replaces the old hardcoded placeholder list in
  /// cda_cooperatives.dart. Deliberately does NOT send an Authorization
  /// header: the backend route is public/no-auth by design (this is
  /// non-sensitive reference data, also needed by the admin panel's
  /// unauthenticated public farmer-registration page), and omitting the
  /// token here means a stale/expired token never blocks loading it.
  Future<List<CdaCooperative>> getCooperatives() async {
    try {
      final url = '$baseUrl/cooperatives';

      _log('API REQUEST - Get Cooperatives: GET $url');

      final response = await http.get(Uri.parse(url)).timeout(_requestTimeout);

      _log('API RESPONSE - Get Cooperatives: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final list = jsonData['data'];
        if (list is! List) return [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(CdaCooperative.fromJson)
            .toList();
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to load cooperatives'),
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

  /// Calls POST /farms with a `farmerId` to attach a NEW farm to an
  /// ALREADY-REGISTERED farmer (backend FarmController.create() - see
  /// comment there on the "Add Farm to Existing Farmer" workflow and its
  /// audit-log entry). Used by the Farmer Detail screen's "Add Farm"
  /// button, reusing the same FarmerFarmDetailsStep + FarmMapWidget
  /// capture flow as brand-new-farmer registration, just scoped to one
  /// farm instead of a whole farmer record.
  ///
  /// [farmDetails] is the raw map produced by
  /// FarmerFarmDetailsStep.onDataChanged (farmName, crop, ownership, etc.)
  /// plus 'boundaryJson' (GeoJSON Feature string), 'areaHa'/'areaAc', and
  /// optionally 'gpsAccuracyM'.
  Future<Map<String, dynamic>> createFarmForFarmer({
    required String farmerId,
    required Map<String, dynamic> farmDetails,
    required String? authToken,
    List<String>? farmPhotoPaths,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/farms'),
      );
      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      request.fields['farmerId'] = farmerId;
      final name = (farmDetails['farmName'] ?? '').toString().trim();
      request.fields['name'] = name.isNotEmpty
          ? name
          : '${farmDetails['crop'] ?? 'Farm'} Plot ${DateTime.now().millisecondsSinceEpoch}';
      if (farmDetails['crop'] != null) {
        request.fields['cropType'] = farmDetails['crop'].toString();
      }
      if (farmDetails['ownership'] != null) {
        request.fields['ownershipType'] = farmDetails['ownership'].toString();
      }
      if (farmDetails['regStatus'] != null &&
          farmDetails['regStatus'].toString().isNotEmpty) {
        request.fields['farmRegistrationStatus'] = farmDetails['regStatus']
            .toString();
      }
      if (farmDetails['farmNotes'] != null) {
        request.fields['farmNotes'] = farmDetails['farmNotes'].toString();
      }
      if (farmDetails['numberOfTrees'] != null) {
        request.fields['numberOfTrees'] = farmDetails['numberOfTrees']
            .toString();
      }
      if (farmDetails['yearsInCultivation'] != null) {
        request.fields['yearsInCultivation'] = farmDetails['yearsInCultivation']
            .toString();
      }
      if (farmDetails['harvestSeason'] != null) {
        request.fields['harvestSeason'] = farmDetails['harvestSeason']
            .toString();
      }
      if (farmDetails['averageYield'] != null) {
        request.fields['averageYield'] = farmDetails['averageYield'].toString();
      }
      if (farmDetails['buyers'] != null) {
        request.fields['buyers'] = farmDetails['buyers'].toString();
      }
      if (farmDetails['farmAddress'] != null) {
        request.fields['farmAddress'] = farmDetails['farmAddress'].toString();
      }
      request.fields['useChemicals'] = (farmDetails['useChemicals'] == true)
          .toString();
      request.fields['extensionServices'] =
          (farmDetails['extensionServices'] == true).toString();
      if (farmDetails['areaHa'] != null &&
          farmDetails['areaHa'].toString().isNotEmpty) {
        request.fields['totalAreaHa'] = farmDetails['areaHa'].toString();
      } else if (farmDetails['farmSizeManual'] != null) {
        request.fields['manualSizeInput'] = farmDetails['farmSizeManual']
            .toString();
        request.fields['manualSizeUnit'] =
            (farmDetails['farmUnitManual'] ?? 'hectares').toString();
      }
      if (farmDetails['gpsAccuracyM'] != null) {
        request.fields['gpsAccuracyM'] = farmDetails['gpsAccuracyM'].toString();
      }

      final boundaryJson = farmDetails['boundaryJson'];
      if (boundaryJson != null && boundaryJson.toString().isNotEmpty) {
        try {
          final decoded = jsonDecode(boundaryJson.toString());
          final geometry = decoded is Map && decoded['geometry'] != null
              ? decoded['geometry']
              : decoded;
          request.fields['location'] = jsonEncode(geometry);
        } catch (_) {
          // Malformed boundary JSON - let the backend's own "Either a
          // GeoJSON 'location' polygon or lat/lng is required" check
          // reject this explicitly rather than silently dropping it here.
        }
      }

      if (farmPhotoPaths != null) {
        for (final path in farmPhotoPaths) {
          final file = File(path);
          if (await file.exists()) {
            request.files.add(
              await http.MultipartFile.fromPath('farmPhotos', path),
            );
          }
        }
      }

      _log(
        'API REQUEST - Create Farm For Farmer: POST ${request.url} (farmerId: $farmerId)',
      );

      final streamedResponse = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      _log('API RESPONSE - Create Farm For Farmer: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonData;
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to create farm'),
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

  /// Calls POST /farms/:id/geometry/revalidate. Note that
  /// [addBoundaryEvidence] above only updates the farm's boundary/location -
  /// it does NOT itself re-run GPS polygon/area validation (see backend
  /// FarmController.addBoundaryEvidence vs revalidateGeometry). This call is
  /// the follow-up step that actually (re)computes geometryStatus,
  /// calculatedAreaHa, overlap checks, etc. for the NEW boundary and returns
  /// the full GeometryValidationResult so the Edit Boundary screen can show
  /// the enumerator an immediate pass/fail/needs-review verdict rather than
  /// silently saving an unvalidated shape.
  ///
  /// Returns the raw `geometryValidation` map from the response, with keys
  /// matching backend GeometryValidationResult (status, errors, warnings,
  /// calculatedAreaHa, areaDifferencePercent, overlapsExistingFarm, etc.).
  Future<Map<String, dynamic>> revalidateFarmGeometry({
    required String farmId,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/farms/$farmId/geometry/revalidate';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Revalidate Farm Geometry: POST $url');

      final response = await http
          .post(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Revalidate Farm Geometry: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final data = jsonData['data'];
        if (data is Map && data['geometryValidation'] is Map) {
          return Map<String, dynamic>.from(data['geometryValidation'] as Map);
        }
        return <String, dynamic>{};
      } else {
        final message = jsonData['message'] as String?;
        throw Exception(message ?? 'Failed to re-validate farm boundary');
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

  /// Fetches a single farm by id (GET /farms/:id) as a [FarmRecord] - used
  /// by the Edit Boundary screen to show the farm's CURRENT boundary/
  /// geometry status before the enumerator re-walks it, and to refresh the
  /// cached geometryStatus display right after a successful re-validation.
  Future<FarmRecord> getFarm({
    required String farmId,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/farms/$farmId';
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Get Farm: GET $url');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Get Farm: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return FarmRecord.fromJson(jsonData['data'] as Map<String, dynamic>);
      } else {
        final message = jsonData['message'] as String?;
        throw Exception(message ?? 'Failed to load farm');
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
    String? clientRecordId,
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
            body: jsonEncode({
              'farmer': farmer,
              'farms': farms,
              if (clientRecordId != null) 'clientRecordId': clientRecordId,
            }),
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

  /// Calls POST /offline-submissions/report with a small, text-only summary
  /// of a farmer registration that was just queued locally (or whose
  /// retry/error state changed). Deliberately tiny (no photos, no boundary
  /// geometry) so it has a real chance of succeeding even on the same weak
  /// connection that made the full multipart registration fail - this is
  /// what gives the backend/admin visibility into "data captured offline
  /// but not yet synced" before the real sync completes.
  ///
  /// Best-effort by design: callers should not treat a failure here as
  /// fatal (the local PendingSyncItem queue is still the source of truth
  /// for the device), so this simply throws and lets the caller decide
  /// whether to swallow the error.
  Future<void> reportOfflineSubmission({
    required String clientId,
    String? displayName,
    String? phoneNumber,
    String? community,
    String? district,
    String? region,
    String? farmName,
    String? cropType,
    int? retryCount,
    String? lastError,
    DateTime? capturedAt,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/offline-submissions/report';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Report Offline Submission: POST $url ($clientId)');

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({
              'clientId': clientId,
              if (displayName != null) 'displayName': displayName,
              if (phoneNumber != null) 'phoneNumber': phoneNumber,
              if (community != null) 'community': community,
              if (district != null) 'district': district,
              if (region != null) 'region': region,
              if (farmName != null) 'farmName': farmName,
              if (cropType != null) 'cropType': cropType,
              if (retryCount != null) 'retryCount': retryCount,
              if (lastError != null) 'lastError': lastError,
              if (capturedAt != null)
                'capturedAt': capturedAt.toIso8601String(),
            }),
          )
          .timeout(_requestTimeout);

      _log('API RESPONSE - Report Offline Submission: ${response.statusCode}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to report offline submission'),
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

  /// Calls POST /offline-submissions/:clientId/resolve once a locally
  /// queued item actually finishes syncing (removes the shadow record from
  /// admin visibility, since the real Farmer now exists) or is discarded by
  /// the inspector. Best-effort - failures here don't affect the local
  /// queue, they only mean the shadow record lingers a bit longer than
  /// ideal.
  Future<void> resolveOfflineSubmission({
    required String clientId,
    String? syncedFarmerId,
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/offline-submissions/$clientId/resolve';
      final headers = {'Content-Type': 'application/json'};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Resolve Offline Submission: POST $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({
              if (syncedFarmerId != null) 'syncedFarmerId': syncedFarmerId,
            }),
          )
          .timeout(_requestTimeout);

      _log('API RESPONSE - Resolve Offline Submission: ${response.statusCode}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to resolve offline submission'),
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

  /// Calls GET /offline-submissions to fetch every farmer registration
  /// currently sitting on ANY inspector's device that hasn't fully synced
  /// yet. Used by OfflineSubmissionsScreen for admin/inspector visibility
  /// into offline field data before it reaches the real Farmer table.
  Future<List<OfflineSubmissionRecord>> getOfflineSubmissions({
    required String? authToken,
  }) async {
    try {
      final url = '$baseUrl/offline-submissions';
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _log('API REQUEST - Get Offline Submissions: GET $url');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);

      _log('API RESPONSE - Get Offline Submissions: ${response.statusCode}');

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final list = jsonData['data'];
        if (list is! List) return [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(OfflineSubmissionRecord.fromJson)
            .toList();
      } else {
        final errors = jsonData['errors'];
        final message = jsonData['message'] as String?;
        throw Exception(
          (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : (message ?? 'Failed to load offline submissions'),
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
