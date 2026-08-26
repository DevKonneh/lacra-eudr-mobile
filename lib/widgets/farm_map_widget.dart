import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gps_service.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

/// Three boundary-capture modes:
/// - [manual]: tap points on the map (existing behaviour).
/// - [autoWalk]: continuous GPS walk, points captured automatically
///   (existing behaviour).
/// - [pointPhoto]: EUDR-standard mode. At least 4 points required; each
///   point ties a precise GPS fix to a photo taken AT that exact spot,
///   producing per-point geotagged evidence (not just a loose photo
///   gallery) that the resulting land polygon is built from.
enum MappingMode { manual, autoWalk, pointPhoto }

class FarmMapWidget extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final Function(Map<String, dynamic>)? onBoundaryDrawn;
  final Function(double areaHa, double areaAc)? onAreaCalculated;
  // EUDR Point + Photo mode: called with the per-point geotagged evidence
  // list, each entry: {sequence, lat, lng, accuracy, timestamp, photoPath}
  // (photoPath is a LOCAL file path - the caller is responsible for
  // uploading it, e.g. via ApiService).
  final Function(List<Map<String, dynamic>>)? onBoundaryEvidenceCaptured;

  const FarmMapWidget({
    super.key,
    this.initialLat,
    this.initialLng,
    this.onBoundaryDrawn,
    this.onAreaCalculated,
    this.onBoundaryEvidenceCaptured,
  });

  @override
  State<FarmMapWidget> createState() => _FarmMapWidgetState();
}

class _FarmMapWidgetState extends State<FarmMapWidget> {
  GoogleMapController? _mapController;
  final Set<Polygon> _polygons = {};
  final Set<Marker> _markers = {};
  final List<LatLng> _polygonPoints = [];
  bool _isDrawing = false;
  double _areaHa = 0.0;
  double _areaAc = 0.0;
  Map<String, dynamic>? _boundaryJson;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  static const String _googleMapsApiKey =
      'AIzaSyDjBhe0NHRAHbAF7-xK8OaCG1LgVIUoulo';

  // Auto-mapping state
  bool _isAutoMapping = false;
  MappingMode _mappingMode = MappingMode.manual;
  final GpsService _gpsService = GpsService();
  double _currentAccuracy = 999.0;
  bool _gpsReady = false;
  Timer? _gpsMonitorTimer;
  Timer? _autoPointCaptureTimer;
  LatLng? _lastCapturedPoint;
  DateTime? _lastCaptureTime;
  int _stableGpsCount = 0;
  StreamSubscription<Position>? _positionStream;

  // ===== EUDR Point + Photo mode state =====
  // Each entry: {sequence, lat, lng, accuracy, timestamp, photoPath, point: LatLng}
  final List<Map<String, dynamic>> _boundaryEvidence = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isCapturingPoint = false; // true while GPS fix + camera flow runs
  static const int _minPointPhotoPoints = 4;

  @override
  void initState() {
    super.initState();
    _updatePolygon();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gpsMonitorTimer?.cancel();
    _autoPointCaptureTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _log('🗺️ Google Map created successfully');

    // Move camera to initial position
    Future.delayed(const Duration(milliseconds: 500), () {
      if (widget.initialLat != null && widget.initialLng != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(widget.initialLat!, widget.initialLng!),
            16.0,
          ),
        );
        _log('📍 Camera moved to: ${widget.initialLat}, ${widget.initialLng}');
      } else {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            const LatLng(6.3156, -10.8074), // Default to Liberia
            8.0,
          ),
        );
        _log('📍 Camera moved to default location: Liberia');
      }
    });
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    try {
      // Use Google Geocoding API for location search
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$_googleMapsApiKey',
      );

      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK' && data['results'] != null) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(data['results']);
        });
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    } catch (e) {
      _log('Error searching location: $e');
      setState(() {
        _searchResults = [];
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final location = result['geometry']['location'];
    final lat = location['lat'] as double;
    final lng = location['lng'] as double;

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16.0),
    );

    setState(() {
      _searchController.text = result['formatted_address'] as String;
      _showSearchResults = false;
    });
  }

  void _calculateArea() {
    if (_polygonPoints.length < 3) {
      _areaHa = 0.0;
      _areaAc = 0.0;
      widget.onAreaCalculated?.call(0.0, 0.0);
      return;
    }

    // Calculate area using spherical excess formula (more accurate for Earth)
    double area = 0.0;
    const double earthRadiusM = 6371000.0; // Earth radius in meters

    for (int i = 0; i < _polygonPoints.length; i++) {
      int j = (i + 1) % _polygonPoints.length;
      double lat1 = _polygonPoints[i].latitude * math.pi / 180.0;
      double lat2 = _polygonPoints[j].latitude * math.pi / 180.0;
      double lon1 = _polygonPoints[i].longitude * math.pi / 180.0;
      double lon2 = _polygonPoints[j].longitude * math.pi / 180.0;

      area += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    area = area.abs() * earthRadiusM * earthRadiusM / 2.0;

    // Convert to hectares (1 hectare = 10,000 m²)
    _areaHa = area / 10000.0;
    _areaAc = _areaHa * 2.47105381; // 1 hectare = 2.47105381 acres

    widget.onAreaCalculated?.call(_areaHa, _areaAc);
  }

  void _onMapTap(LatLng position) {
    // Only allow manual tapping in manual mode
    if (_isDrawing && _mappingMode == MappingMode.manual) {
      setState(() {
        _polygonPoints.add(position);
        _updatePolygon();
        _calculateArea();
      });
    }
  }

  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _polygonPoints.clear();
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
      _showSearchResults = false;
    });
  }

  void _finishDrawing() {
    if (_polygonPoints.length >= 3) {
      setState(() {
        _isDrawing = false;
        _updateBoundary();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Polygon completed! Tap "Save" in the top bar to save the boundary.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least 3 points to create a polygon'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _resetPolygon() {
    setState(() {
      _polygonPoints.clear();
      _isDrawing = false;
      _areaHa = 0.0;
      _areaAc = 0.0;
      _boundaryJson = null;
      _updatePolygon();
      _updateBoundary();
    });
  }

  void _updatePolygon() {
    _polygons.clear();
    _markers.clear();

    if (_mappingMode == MappingMode.pointPhoto) {
      final pts = _boundaryEvidence
          .map((e) => e['point'] as LatLng)
          .toList(growable: false);
      if (pts.length >= 3) {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('farm_boundary'),
            points: [...pts, pts[0]],
            fillColor: const Color(0xFF4CAF50).withOpacity(0.3),
            strokeColor: const Color(0xFF4CAF50),
            strokeWidth: 3,
            geodesic: true,
          ),
        );
      }
      for (int i = 0; i < pts.length; i++) {
        final accuracy = (_boundaryEvidence[i]['accuracy'] as double?) ?? 0.0;
        _markers.add(
          Marker(
            markerId: MarkerId('evidence_point_$i'),
            position: pts[i],
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
            infoWindow: InfoWindow(
              title: 'Point ${i + 1} (photo captured)',
              snippet: '±${accuracy.toStringAsFixed(1)}m',
            ),
          ),
        );
      }
      return;
    }

    if (_polygonPoints.isNotEmpty) {
      // Add polygon if we have at least 3 points
      if (_polygonPoints.length >= 3) {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('farm_boundary'),
            points: [..._polygonPoints, _polygonPoints[0]], // Close the polygon
            fillColor: const Color(0xFF4CAF50).withOpacity(0.3),
            strokeColor: const Color(0xFF4CAF50),
            strokeWidth: 3,
            geodesic: true,
          ),
        );
      }

      // Add markers for each point
      for (int i = 0; i < _polygonPoints.length; i++) {
        _markers.add(
          Marker(
            markerId: MarkerId('point_$i'),
            position: _polygonPoints[i],
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(title: 'Point ${i + 1}'),
          ),
        );
      }
    }
  }

  void _updateBoundary() {
    if (_polygonPoints.length >= 3) {
      // Create GeoJSON Feature structure
      final coordinates = _polygonPoints
          .map((p) => [p.longitude, p.latitude])
          .toList();
      // Close the polygon by adding the first point at the end
      coordinates.add([
        _polygonPoints[0].longitude,
        _polygonPoints[0].latitude,
      ]);

      _boundaryJson = {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coordinates],
        },
      };
      widget.onBoundaryDrawn?.call(_boundaryJson!);
    } else {
      _boundaryJson = null;
      widget.onBoundaryDrawn?.call({});
    }
  }

  void _saveAndClose() {
    if (_mappingMode == MappingMode.pointPhoto) {
      _finishPointPhotoMapping();
      return;
    }
    if (_polygonPoints.length >= 3) {
      _updateBoundary();
      Navigator.of(context).pop({
        'boundary': _boundaryJson,
        'areaHa': _areaHa,
        'areaAc': _areaAc,
        'points': _polygonPoints.length,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least 3 points to create a polygon before saving',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ============ EUDR POINT + PHOTO MODE ============
  // Minimum 4 geotagged points required (real farm shapes with 5+ corners
  // still work - there is no upper cap). Each point captures a precise GPS
  // fix FIRST, then immediately opens the camera so the photo is proof of
  // standing at that exact coordinate - this is what distinguishes the mode
  // from a generic photo gallery attached after the fact.

  Future<void> _capturePointWithPhoto() async {
    if (_isCapturingPoint) return;
    setState(() => _isCapturingPoint = true);

    try {
      // 1. Get a precise GPS fix for this point.
      final position = await _gpsService.getCurrentLocation(
        timeLimit: const Duration(seconds: 15),
      );

      if (position == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get GPS location. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (position.accuracy > 20.0) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Low GPS Accuracy'),
            content: Text(
              'Current accuracy is ±${position.accuracy.toStringAsFixed(1)}m. '
              'For best results, move to open sky and try again. '
              'Capture this point anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Capture Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }

      if (!mounted) return;

      // 2. Immediately capture a photo AT this point.
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) {
        // User cancelled the camera - don't record a point without evidence.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Point not saved - a photo is required for each point.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      final sequence = _boundaryEvidence.length;

      setState(() {
        _boundaryEvidence.add({
          'sequence': sequence,
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
          'photoPath': photo.path,
          'point': point,
        });
        _updatePolygon();
        _calculatePointPhotoArea();
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(point));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Point ${_boundaryEvidence.length} captured '
            '(±${position.accuracy.toStringAsFixed(1)}m)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture point: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturingPoint = false);
    }
  }

  void _removeLastEvidencePoint() {
    if (_boundaryEvidence.isEmpty) return;
    setState(() {
      _boundaryEvidence.removeLast();
      _updatePolygon();
      _calculatePointPhotoArea();
    });
  }

  void _resetPointPhotoMapping() {
    setState(() {
      _boundaryEvidence.clear();
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
    });
  }

  void _calculatePointPhotoArea() {
    final pts = _boundaryEvidence
        .map((e) => e['point'] as LatLng)
        .toList(growable: false);
    if (pts.length < 3) {
      _areaHa = 0.0;
      _areaAc = 0.0;
      widget.onAreaCalculated?.call(0.0, 0.0);
      return;
    }

    double area = 0.0;
    const double earthRadiusM = 6371000.0;
    for (int i = 0; i < pts.length; i++) {
      int j = (i + 1) % pts.length;
      double lat1 = pts[i].latitude * math.pi / 180.0;
      double lat2 = pts[j].latitude * math.pi / 180.0;
      double lon1 = pts[i].longitude * math.pi / 180.0;
      double lon2 = pts[j].longitude * math.pi / 180.0;
      area += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2));
    }
    area = area.abs() * earthRadiusM * earthRadiusM / 2.0;
    _areaHa = area / 10000.0;
    _areaAc = _areaHa * 2.47105381;
    widget.onAreaCalculated?.call(_areaHa, _areaAc);
  }

  void _finishPointPhotoMapping() {
    if (_boundaryEvidence.length < _minPointPhotoPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'At least $_minPointPhotoPoints points (each with a photo) are '
            'required to create an EUDR-standard boundary. '
            'Captured so far: ${_boundaryEvidence.length}.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _calculatePointPhotoArea();

    final pts = _boundaryEvidence
        .map((e) => e['point'] as LatLng)
        .toList(growable: false);
    final coordinates = pts.map((p) => [p.longitude, p.latitude]).toList();
    coordinates.add([pts[0].longitude, pts[0].latitude]);

    final boundary = {
      'type': 'Feature',
      'properties': {},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [coordinates],
      },
    };

    // Evidence payload for the caller (strip the internal LatLng helper).
    final evidence = _boundaryEvidence
        .map(
          (e) => {
            'sequence': e['sequence'],
            'lat': e['lat'],
            'lng': e['lng'],
            'accuracy': e['accuracy'],
            'timestamp': e['timestamp'],
            'photoPath': e['photoPath'],
          },
        )
        .toList();

    widget.onBoundaryDrawn?.call(boundary);
    widget.onBoundaryEvidenceCaptured?.call(evidence);

    Navigator.of(context).pop({
      'boundary': boundary,
      'areaHa': _areaHa,
      'areaAc': _areaAc,
      'points': _boundaryEvidence.length,
      'boundaryEvidence': evidence,
    });
  }

  // ============ AUTO-MAPPING FUNCTIONS ============

  Future<void> _startGpsMonitoring() async {
    _gpsMonitorTimer?.cancel();
    _stableGpsCount = 0;
    _gpsReady = false;

    _gpsMonitorTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      try {
        final position = await _gpsService.getCurrentLocation(
          timeLimit: const Duration(seconds: 5),
        );

        if (position != null) {
          setState(() {
            _currentAccuracy = position.accuracy;

            if (_currentAccuracy <= 8.0) {
              _stableGpsCount++;
              if (_stableGpsCount >= 10) {
                _gpsReady = true;
              }
            } else {
              _stableGpsCount = 0;
              _gpsReady = false;
            }
          });
        }
      } catch (e) {
        setState(() {
          _currentAccuracy = 999.0;
          _gpsReady = false;
          _stableGpsCount = 0;
        });
      }
    });
  }

  void _stopGpsMonitoring() {
    _gpsMonitorTimer?.cancel();
    _stableGpsCount = 0;
    _gpsReady = false;
  }

  Future<void> _startAutoMapping() async {
    if (!_gpsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS not ready. Wait for stable signal.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAutoMapping = true;
      _polygonPoints.clear();
      _lastCapturedPoint = null;
      _lastCaptureTime = null;
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
      _showSearchResults = false;
    });

    _startAutoPointCapture();
  }

  void _startAutoPointCapture() {
    _autoPointCaptureTimer?.cancel();

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // Minimum 5 meters movement
          ),
        ).listen((position) async {
          if (!_isAutoMapping) return;

          final now = DateTime.now();
          final currentPoint = LatLng(position.latitude, position.longitude);

          // Quality gate: Only accept points with good accuracy
          if (position.accuracy > 8.0) {
            return;
          }

          // Time check: At least 5 seconds since last capture
          if (_lastCaptureTime != null) {
            final timeDiff = now.difference(_lastCaptureTime!).inSeconds;
            if (timeDiff < 5) {
              return;
            }
          }

          // Distance check: At least 5 meters from last point
          if (_lastCapturedPoint != null) {
            final distance = _calculateDistance(
              _lastCapturedPoint!.latitude,
              _lastCapturedPoint!.longitude,
              currentPoint.latitude,
              currentPoint.longitude,
            );

            // Outlier detection: Reject points that jump > 25m in < 5 seconds
            final timeSinceLastCapture = _lastCaptureTime != null
                ? now.difference(_lastCaptureTime!).inSeconds
                : 999;
            if (distance > 25 && timeSinceLastCapture < 5) {
              _log('🚫 Outlier rejected: ${distance.toStringAsFixed(1)}m jump');
              return;
            }

            if (distance < 5) {
              return;
            }
          }

          // Capture the point
          setState(() {
            _polygonPoints.add(currentPoint);
            _lastCapturedPoint = currentPoint;
            _lastCaptureTime = now;
            _updatePolygon();
            _calculateArea();
          });

          // Move camera to follow user
          _mapController?.animateCamera(CameraUpdate.newLatLng(currentPoint));

          _log(
            '✅ Point captured: ${_polygonPoints.length} (accuracy: ${position.accuracy.toStringAsFixed(1)}m)',
          );
        });
  }

  void _finishAutoMapping() {
    if (_polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least 3 points to create boundary'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check closure distance
    final firstPoint = _polygonPoints.first;
    final lastPoint = _polygonPoints.last;
    final closureDistance = _calculateDistance(
      firstPoint.latitude,
      firstPoint.longitude,
      lastPoint.latitude,
      lastPoint.longitude,
    );

    if (closureDistance > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You are ${closureDistance.toStringAsFixed(1)}m from the start. Walk closer to close the boundary.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Check for self-intersection (basic check)
    if (_hasSelfintersection()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Boundary has invalid crossing. Please redo mapping.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Stop auto-capture
    _positionStream?.cancel();

    setState(() {
      _isAutoMapping = false;
      _updatePolygon();
      _calculateArea();
      _updateBoundary();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Boundary captured! Area: ${_areaHa.toStringAsFixed(4)} ha',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _cancelAutoMapping() {
    _positionStream?.cancel();
    setState(() {
      _isAutoMapping = false;
      _polygonPoints.clear();
      _lastCapturedPoint = null;
      _lastCaptureTime = null;
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
    });
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  bool _hasSelfintersection() {
    if (_polygonPoints.length < 4) return false;

    for (int i = 0; i < _polygonPoints.length - 1; i++) {
      for (int j = i + 2; j < _polygonPoints.length - 1; j++) {
        if (i == 0 && j == _polygonPoints.length - 2) {
          continue; // Skip adjacent segments
        }

        if (_segmentsIntersect(
          _polygonPoints[i],
          _polygonPoints[i + 1],
          _polygonPoints[j],
          _polygonPoints[j + 1],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _segmentsIntersect(LatLng a1, LatLng a2, LatLng b1, LatLng b2) {
    final d1 = _crossProduct(b1, b2, a1);
    final d2 = _crossProduct(b1, b2, a2);
    final d3 = _crossProduct(a1, a2, b1);
    final d4 = _crossProduct(a1, a2, b2);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  double _crossProduct(LatLng o, LatLng a, LatLng b) {
    return (a.latitude - o.latitude) * (b.longitude - o.longitude) -
        (a.longitude - o.longitude) * (b.latitude - o.latitude);
  }

  // Cycles Manual -> Auto GPS Walk -> Point + Photo (EUDR) -> Manual ...
  void _switchMappingMode() {
    setState(() {
      switch (_mappingMode) {
        case MappingMode.manual:
          _mappingMode = MappingMode.autoWalk;
          break;
        case MappingMode.autoWalk:
          _mappingMode = MappingMode.pointPhoto;
          break;
        case MappingMode.pointPhoto:
          _mappingMode = MappingMode.manual;
          break;
      }

      _polygonPoints.clear();
      _boundaryEvidence.clear();
      _isDrawing = false;
      _isAutoMapping = false;
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
      _positionStream?.cancel();
      _autoPointCaptureTimer?.cancel();
      _stopGpsMonitoring();

      if (_mappingMode == MappingMode.autoWalk) {
        _startGpsMonitoring();
      }
    });
  }

  String _modeTitle() {
    switch (_mappingMode) {
      case MappingMode.manual:
        return 'Manual Mapping';
      case MappingMode.autoWalk:
        return 'Auto GPS Mapping';
      case MappingMode.pointPhoto:
        return 'EUDR Point + Photo Mapping';
    }
  }

  bool get _canSave {
    if (_mappingMode == MappingMode.pointPhoto) {
      return _boundaryEvidence.length >= _minPointPhotoPoints;
    }
    return _polygonPoints.length >= 3 && !_isAutoMapping;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_modeTitle()),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          if (_canSave)
            TextButton.icon(
              onPressed: _saveAndClose,
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Full screen map
          SizedBox.expand(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: widget.initialLat != null && widget.initialLng != null
                    ? LatLng(widget.initialLat!, widget.initialLng!)
                    : const LatLng(6.3156, -10.8074), // Default to Liberia
                zoom: widget.initialLat != null && widget.initialLng != null
                    ? 16.0
                    : 8.0,
              ),
              onTap: _onMapTap,
              polygons: _polygons,
              markers: _markers,
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: false, // We'll add custom button
              zoomControlsEnabled: true,
              compassEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),

          // Search bar at top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search location...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _showSearchResults = false;
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          _searchLocation(value);
                        } else {
                          setState(() {
                            _searchResults = [];
                            _showSearchResults = false;
                          });
                        }
                      },
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          _searchLocation(value);
                        }
                      },
                    ),
                  ),

                  // Search results
                  if (_showSearchResults && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length > 5
                            ? 5
                            : _searchResults.length,
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.location_on,
                              color: Color(0xFF4CAF50),
                            ),
                            title: Text(
                              result['formatted_address'] as String? ?? '',
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),

                  if (_isSearching)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Searching...'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Drawing controls at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.grey.shade50],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _polygonPoints.length >= 3
                                  ? [
                                      const Color(0xFF4CAF50).withOpacity(0.15),
                                      const Color(0xFF4CAF50).withOpacity(0.05),
                                    ]
                                  : [
                                      Colors.grey.shade200,
                                      Colors.grey.shade100,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _polygonPoints.length >= 3
                                  ? const Color(0xFF4CAF50).withOpacity(0.3)
                                  : Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: _polygonPoints.length >= 3
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_polygonPoints.length} Points',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _polygonPoints.length >= 3
                                      ? const Color(0xFF388E3C)
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_areaHa > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade100.withOpacity(0.5),
                                  Colors.blue.shade50,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.blue.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.crop_free,
                                  size: 14,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_areaHa.toStringAsFixed(4)} ha',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade100.withOpacity(0.5),
                                  Colors.blue.shade50,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.blue.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.square_foot,
                                  size: 14,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_areaAc.toStringAsFixed(4)} ac',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Mode switcher button
                    InkWell(
                      onTap: _switchMappingMode,
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF4CAF50).withOpacity(0.15),
                              const Color(0xFF4CAF50).withOpacity(0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: const Color(0xFF4CAF50),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4CAF50).withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              switch (_mappingMode) {
                                MappingMode.manual => Icons.gps_fixed,
                                MappingMode.autoWalk => Icons.camera_alt,
                                MappingMode.pointPhoto => Icons.touch_app,
                              },
                              size: 18,
                              color: const Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              switch (_mappingMode) {
                                MappingMode.manual => 'Switch to Auto GPS Walk',
                                MappingMode.autoWalk =>
                                  'Switch to EUDR Point + Photo',
                                MappingMode.pointPhoto =>
                                  'Switch to Manual Drawing',
                              },
                              style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Action buttons - different per mode
                    if (_mappingMode == MappingMode.pointPhoto) ...[
                      // EUDR POINT + PHOTO MODE BUTTONS
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              _boundaryEvidence.length >= _minPointPhotoPoints
                              ? Colors.green.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                _boundaryEvidence.length >= _minPointPhotoPoints
                                ? Colors.green.shade200
                                : Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 18,
                              color:
                                  _boundaryEvidence.length >=
                                      _minPointPhotoPoints
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_boundaryEvidence.length} / $_minPointPhotoPoints+ points captured (each with a photo)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _boundaryEvidence.length >=
                                          _minPointPhotoPoints
                                      ? Colors.green.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: _isCapturingPoint
                                  ? null
                                  : _capturePointWithPhoto,
                              icon: _isCapturingPoint
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.add_a_photo),
                              label: Text(
                                _isCapturingPoint
                                    ? 'Capturing...'
                                    : 'Capture Point + Photo',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4CAF50),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: const Color(
                                  0xFF4CAF50,
                                ).withOpacity(0.4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _boundaryEvidence.isNotEmpty
                                  ? _removeLastEvidencePoint
                                  : null,
                              icon: const Icon(Icons.undo),
                              label: const Text('Undo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: Colors.orange.withOpacity(0.4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_boundaryEvidence.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _resetPointPhotoMapping,
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'Reset All',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ] else if (_mappingMode == MappingMode.manual) ...[
                      // MANUAL MODE BUTTONS
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: _isDrawing
                                  ? _finishDrawing
                                  : _startDrawing,
                              icon: Icon(_isDrawing ? Icons.check : Icons.edit),
                              label: Text(
                                _isDrawing ? 'Finish Drawing' : 'Start Drawing',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isDrawing
                                    ? Colors.orange
                                    : const Color(0xFF4CAF50),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor:
                                    (_isDrawing
                                            ? Colors.orange
                                            : const Color(0xFF4CAF50))
                                        .withOpacity(0.4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _polygonPoints.isNotEmpty
                                  ? _resetPolygon
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Reset'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: Colors.red.withOpacity(0.4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // AUTO MODE BUTTONS
                      if (!_isAutoMapping) ...[
                        // GPS Status indicator
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _gpsReady
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _gpsReady
                                  ? Colors.green.shade200
                                  : Colors.orange.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _gpsReady
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                                color: _gpsReady ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _gpsReady
                                          ? 'GPS Ready'
                                          : 'Waiting for GPS...',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: _gpsReady
                                            ? Colors.green.shade900
                                            : Colors.orange.shade900,
                                      ),
                                    ),
                                    Text(
                                      'Accuracy: ±${_currentAccuracy.toStringAsFixed(1)}m ${_gpsReady ? '' : '($_stableGpsCount/10s)'}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    if (!_gpsReady)
                                      const Text(
                                        'Move to open sky for better signal',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _gpsReady ? _startAutoMapping : null,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start Mapping'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: const Color(
                                    0xFF4CAF50,
                                  ).withOpacity(0.4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // During auto-mapping
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: _finishAutoMapping,
                                icon: const Icon(Icons.check_circle),
                                label: const Text('Finish'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: Colors.orange.withOpacity(0.4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _cancelAutoMapping,
                                icon: const Icon(Icons.cancel),
                                label: const Text('Cancel'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: Colors.red.withOpacity(0.4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Drawing instruction
                    if (_isDrawing)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tap on the map to add points. Add at least 3 points to create a polygon.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Auto-mapping instruction
                    if (_isAutoMapping)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.directions_walk,
                              color: Colors.blue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Walk around the farm boundary. Points are captured automatically every 5 seconds or 5 meters.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // EUDR Point + Photo instruction
                    if (_mappingMode == MappingMode.pointPhoto)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.eco,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Walk to each corner of the farm boundary and tap "Capture Point + Photo". '
                                'A GPS fix is taken first, then the camera opens - each point requires its own photo. '
                                'Capture at least $_minPointPhotoPoints points to complete the boundary.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // My location button
          Positioned(
            right: 16,
            bottom: 200,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () async {
                try {
                  final position = await _gpsService.getCurrentLocation(
                    timeLimit: const Duration(seconds: 10),
                  );

                  if (position != null && _mapController != null) {
                    _mapController!.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(position.latitude, position.longitude),
                        18.0,
                      ),
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                        ),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF4CAF50),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to get location: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Icon(Icons.my_location, color: Color(0xFF4CAF50)),
            ),
          ),
        ],
      ),
    );
  }
}
