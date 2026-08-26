import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gps_service.dart';
import '../services/auth_service.dart';

class FarmerLocationStep extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataChanged;
  final Map<String, dynamic>? initialData;

  const FarmerLocationStep({
    super.key,
    required this.onDataChanged,
    this.initialData,
  });

  @override
  State<FarmerLocationStep> createState() => _FarmerLocationStepState();
}

class _FarmerLocationStepState extends State<FarmerLocationStep> {
  final _formKey = GlobalKey<FormState>();
  final _countyController = TextEditingController();
  final _districtController = TextEditingController();
  final _communityController = TextEditingController();
  final _inspectorNameController = TextEditingController();
  final _enumeratorIdController = TextEditingController();
  final _directionsController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final GpsService _gpsService = GpsService();
  final AuthService _authService = AuthService();
  bool _isCapturingGps = false;
  String _gpsStatus = 'GPS: Not captured';
  String _gpsTime = 'Time: —';

  // Liberian counties
  static const List<String> _liberianCounties = [
    'Bomi',
    'Bong',
    'Gbarpolu',
    'Grand Bassa',
    'Grand Cape Mount',
    'Grand Gedeh',
    'Grand Kru',
    'Lofa',
    'Margibi',
    'Maryland',
    'Montserrado',
    'Nimba',
    'River Cess',
    'River Gee',
    'Sinoe',
  ];

  @override
  void initState() {
    super.initState();
    _loadInspectorName();
    if (widget.initialData != null) {
      _countyController.text = widget.initialData!['county'] ?? '';
      _districtController.text = widget.initialData!['district'] ?? '';
      _communityController.text = widget.initialData!['community'] ?? '';
      _inspectorNameController.text =
          widget.initialData!['inspectorName'] ?? '';
      _enumeratorIdController.text = widget.initialData!['enumeratorId'] ?? '';
      _directionsController.text = widget.initialData!['directions'] ?? '';
      if (widget.initialData!['lat'] != null) {
        _latController.text = widget.initialData!['lat'].toString();
      }
      if (widget.initialData!['lng'] != null) {
        _lngController.text = widget.initialData!['lng'].toString();
      }
      _gpsStatus = widget.initialData!['lat'] != null
          ? 'GPS: Captured'
          : 'GPS: Not captured';
    }
    _updateData();
  }

  @override
  void dispose() {
    _countyController.dispose();
    _districtController.dispose();
    _communityController.dispose();
    _inspectorNameController.dispose();
    _enumeratorIdController.dispose();
    _directionsController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _updateData() {
    widget.onDataChanged({
      'county': _countyController.text.trim(),
      'district': _districtController.text.trim(),
      'community': _communityController.text.trim(),
      'inspectorName': _inspectorNameController.text.trim(),
      'enumeratorId': _enumeratorIdController.text.trim(),
      'directions': _directionsController.text.trim(),
      'lat': _latController.text.isNotEmpty
          ? double.tryParse(_latController.text)
          : null,
      'lng': _lngController.text.isNotEmpty
          ? double.tryParse(_lngController.text)
          : null,
    });
  }

  Future<void> _captureGPS() async {
    setState(() {
      _isCapturingGps = true;
      _gpsStatus = 'GPS: Capturing...';
    });

    try {
      final position = await _gpsService.getCurrentLocation(
        timeLimit: const Duration(seconds: 30),
        accuracy: LocationAccuracy.high,
      );
      if (position != null) {
        setState(() {
          _latController.text = position.latitude.toStringAsFixed(6);
          _lngController.text = position.longitude.toStringAsFixed(6);
          final timestamp = position.timestamp;
          _gpsTime = 'Time: ${timestamp.toLocal().toString().substring(0, 19)}';
          _gpsStatus =
              'GPS: Captured (±${position.accuracy.toStringAsFixed(0)}m)';
          _updateData();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS coordinates captured successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _gpsStatus = 'GPS: Error - ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture GPS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isCapturingGps = false;
      });
    }
  }

  bool validate() {
    return _formKey.currentState?.validate() ?? false;
  }

  Future<void> _loadInspectorName() async {
    final user = await _authService.getUser();
    if (user != null && mounted) {
      setState(() {
        _inspectorNameController.text = user.name;
        _updateData();
      });
    }
  }

  void _showCountyBottomSheet() {
    final TextEditingController searchController = TextEditingController();
    List<String> filteredCounties = List.from(_liberianCounties);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterCounties(String query) {
              setModalState(() {
                if (query.isEmpty) {
                  filteredCounties = List.from(_liberianCounties);
                } else {
                  filteredCounties = _liberianCounties
                      .where(
                        (county) =>
                            county.toLowerCase().contains(query.toLowerCase()),
                      )
                      .toList();
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select County',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search field
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search county...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filterCounties('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                    onChanged: filterCounties,
                  ),
                  const SizedBox(height: 16),

                  // County list
                  Expanded(
                    child: filteredCounties.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No counties found',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredCounties.length,
                            itemBuilder: (context, index) {
                              final county = filteredCounties[index];
                              final isSelected =
                                  _countyController.text == county;
                              return ListTile(
                                title: Text(county),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Color(0xFF4CAF50),
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor: const Color(
                                  0xFF4CAF50,
                                ).withOpacity(0.1),
                                onTap: () {
                                  setState(() {
                                    _countyController.text = county;
                                    _updateData();
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      onChanged: _updateData,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            TextFormField(
              controller: _countyController,
              style: const TextStyle(fontSize: 14),
              readOnly: true,
              onTap: _showCountyBottomSheet,
              decoration: const InputDecoration(
                labelText: 'County *',
                hintText: 'Select county',
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'County is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _districtController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'District',
                hintText: 'e.g., District #3',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _communityController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Community / Town / Village *',
                hintText: 'e.g., Gbarnga Town',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Community is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _inspectorNameController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Enumerator / Inspector Name *',
                hintText: 'Logged in user',
                filled: true,
                fillColor: Color(0xFFF5F5F5),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Inspector name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _enumeratorIdController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Enumerator / Inspector ID (Optional)',
                hintText: 'e.g., INSP-014',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isCapturingGps ? null : _captureGPS,
              icon: _isCapturingGps
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.location_on, size: 18),
              label: Text(
                _isCapturingGps ? 'Capturing...' : 'Capture GPS',
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                minimumSize: const Size(0, 36),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(
                  label: Text(_gpsStatus),
                  backgroundColor: _gpsStatus.contains('Captured')
                      ? Colors.green.shade50
                      : Colors.grey.shade200,
                ),
                Chip(
                  label: Text(_gpsTime),
                  backgroundColor: Colors.blue.shade50,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _latController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: '—',
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lngController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: '—',
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _directionsController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Directions to Farm (optional)',
                hintText: 'Landmarks, road description...',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
