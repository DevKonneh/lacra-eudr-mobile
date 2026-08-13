import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../services/gps_service.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

class FarmMapWidget extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final Function(Map<String, dynamic>)? onBoundaryDrawn;
  final Function(double areaHa, double areaAc)? onAreaCalculated;

  const FarmMapWidget({
    super.key,
    this.initialLat,
    this.initialLng,
    this.onBoundaryDrawn,
    this.onAreaCalculated,
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
  bool _mappingMode = false; // false = manual, true = auto
  final GpsService _gpsService = GpsService();
  double _currentAccuracy = 999.0;
  bool _gpsReady = false;
  Timer? _gpsMonitorTimer;
  Timer? _autoPointCaptureTimer;
  LatLng? _lastCapturedPoint;
  DateTime? _lastCaptureTime;
  int _stableGpsCount = 0;
  StreamSubscription<Position>? _positionStream;

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
    if (_isDrawing && !_mappingMode) {
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

  void _switchMappingMode() {
    setState(() {
      _mappingMode = !_mappingMode;
      _polygonPoints.clear();
      _isDrawing = false;
      _isAutoMapping = false;
      _areaHa = 0.0;
      _areaAc = 0.0;
      _updatePolygon();
      _positionStream?.cancel();
      _autoPointCaptureTimer?.cancel();

      if (_mappingMode) {
        // Switching to auto mode
        _startGpsMonitoring();
      } else {
        // Switching to manual mode
        _stopGpsMonitoring();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mappingMode ? 'Auto GPS Mapping' : 'Manual Mapping'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          if (_polygonPoints.length >= 3 && !_isAutoMapping)
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
                              _mappingMode ? Icons.touch_app : Icons.gps_fixed,
                              size: 18,
                              color: const Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _mappingMode
                                  ? 'Switch to Manual Drawing'
                                  : 'Switch to Auto GPS Walk',
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

                    // Action buttons - Different for Manual vs Auto mode
                    if (!_mappingMode) ...[
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
