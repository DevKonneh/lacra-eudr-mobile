import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/liberia_locations.dart';
import '../services/gps_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// GPS accuracy (meters) above which we warn the enumerator and suggest a
/// retry instead of silently accepting a low-quality fix (task spec
/// section 6).
const double _kPoorGpsAccuracyThresholdMeters = 30;

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
  final _directionsController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final GpsService _gpsService = GpsService();
  final AuthService _authService = AuthService();
  bool _isCapturingGps = false;
  String _gpsStatus = 'GPS: Not captured';
  String _gpsTime = 'Time: —';
  double? _gpsAccuracyMeters;
  String? _gpsCapturedAtIso;

  // Enumerator/inspector identity - populated automatically in the
  // background from the logged-in user (task spec section 7: the field
  // must NOT be shown/editable in the form UI, but the value must still be
  // attached to every registration behind the scenes).
  String _inspectorName = '';
  String _enumeratorId = '';

  @override
  void initState() {
    super.initState();
    _loadInspectorIdentity();
    if (widget.initialData != null) {
      _countyController.text = widget.initialData!['county'] ?? '';
      _districtController.text = widget.initialData!['district'] ?? '';
      _communityController.text = widget.initialData!['community'] ?? '';
      // Preserve any previously auto-populated values (e.g. resuming a
      // draft/pending item) as a fallback until _loadInspectorIdentity
      // confirms the currently logged-in user.
      _inspectorName = widget.initialData!['inspectorName'] ?? '';
      _enumeratorId = widget.initialData!['enumeratorId'] ?? '';
      _directionsController.text = widget.initialData!['directions'] ?? '';
      if (widget.initialData!['lat'] != null) {
        _latController.text = widget.initialData!['lat'].toString();
      }
      if (widget.initialData!['lng'] != null) {
        _lngController.text = widget.initialData!['lng'].toString();
      }
      final accuracyRaw = widget.initialData!['gpsAccuracy'];
      if (accuracyRaw != null) {
        _gpsAccuracyMeters = (accuracyRaw as num).toDouble();
      }
      _gpsCapturedAtIso = widget.initialData!['gpsCapturedAt'];
      if (widget.initialData!['lat'] != null) {
        _gpsStatus = _gpsAccuracyMeters != null
            ? 'GPS Location Captured'
            : 'GPS: Captured';
        if (_gpsCapturedAtIso != null) {
          _gpsTime = 'Time: $_gpsCapturedAtIso';
        }
      }
    }
    _updateData();
  }

  @override
  void dispose() {
    _countyController.dispose();
    _districtController.dispose();
    _communityController.dispose();
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
      // Auto-attached in the background - not editable via this form's UI.
      'inspectorName': _inspectorName,
      'enumeratorId': _enumeratorId,
      'directions': _directionsController.text.trim(),
      'lat': _latController.text.isNotEmpty
          ? double.tryParse(_latController.text)
          : null,
      'lng': _lngController.text.isNotEmpty
          ? double.tryParse(_lngController.text)
          : null,
      'gpsAccuracy': _gpsAccuracyMeters,
      'gpsCapturedAt': _gpsCapturedAtIso,
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
        final accuracy = position.accuracy;
        setState(() {
          _latController.text = position.latitude.toStringAsFixed(6);
          _lngController.text = position.longitude.toStringAsFixed(6);
          final timestamp = position.timestamp;
          _gpsCapturedAtIso = timestamp.toIso8601String();
          _gpsTime = 'Time: ${timestamp.toLocal().toString().substring(0, 19)}';
          _gpsAccuracyMeters = accuracy;
          _gpsStatus = 'GPS Location Captured';
          _updateData();
        });

        if (accuracy > _kPoorGpsAccuracyThresholdMeters) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'GPS accuracy is currently ${accuracy.toStringAsFixed(0)} '
                  'meters. Please move to an open area and try again.',
                ),
                backgroundColor: AppTheme.warning,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'RETRY',
                  textColor: Colors.white,
                  onPressed: _captureGPS,
                ),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'GPS Location Captured - Accuracy: '
                '${accuracy.toStringAsFixed(0)} meters',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _gpsStatus = 'GPS: Error - ${e.toString()}';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture GPS: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingGps = false;
        });
      }
    }
  }

  bool validate() {
    return _formKey.currentState?.validate() ?? false;
  }

  Future<void> _loadInspectorIdentity() async {
    final user = await _authService.getUser();
    if (user != null && mounted) {
      setState(() {
        _inspectorName = user.name;
        _enumeratorId = user.id;
        _updateData();
      });
    }
  }

  void _showCountyBottomSheet() {
    final TextEditingController searchController = TextEditingController();
    List<String> filteredCounties = List.from(LiberiaLocations.counties);

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
                  filteredCounties = List.from(LiberiaLocations.counties);
                } else {
                  filteredCounties = LiberiaLocations.counties
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
                      fillColor: AppTheme.background,
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
                                const Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No counties found',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
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
                                        color: AppTheme.primaryGreen,
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor: AppTheme.paleGreen,
                                onTap: () {
                                  setState(() {
                                    if (_countyController.text != county) {
                                      // District list depends on county -
                                      // reset it whenever county changes so
                                      // a stale district from a different
                                      // county can never be submitted.
                                      _districtController.clear();
                                    }
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

  void _showDistrictBottomSheet() {
    final selectedCounty = _countyController.text.trim();
    final districts = LiberiaLocations.districtsFor(
      selectedCounty.isEmpty ? null : selectedCounty,
    );
    if (districts.isEmpty) return;

    final TextEditingController searchController = TextEditingController();
    List<String> filteredDistricts = List.from(districts);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterDistricts(String query) {
              setModalState(() {
                if (query.isEmpty) {
                  filteredDistricts = List.from(districts);
                } else {
                  filteredDistricts = districts
                      .where((d) =>
                          d.toLowerCase().contains(query.toLowerCase()))
                      .toList();
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select District ($selectedCounty)',
                        style: const TextStyle(
                          fontSize: 16,
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
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search district...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filterDistricts('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: AppTheme.background,
                    ),
                    onChanged: filterDistricts,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredDistricts.isEmpty
                        ? const Center(
                            child: Text(
                              'No districts found',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredDistricts.length,
                            itemBuilder: (context, index) {
                              final district = filteredDistricts[index];
                              final isSelected =
                                  _districtController.text == district;
                              return ListTile(
                                title: Text(district),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: AppTheme.primaryGreen,
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor: AppTheme.paleGreen,
                                onTap: () {
                                  setState(() {
                                    _districtController.text = district;
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
    final hasCounty = _countyController.text.trim().isNotEmpty;
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
              readOnly: true,
              onTap: hasCounty ? _showDistrictBottomSheet : null,
              decoration: InputDecoration(
                labelText: 'District *',
                hintText: hasCounty
                    ? 'Select district'
                    : 'Select a county first',
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please select a district.';
                }
                return null;
              },
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isCapturingGps ? null : _captureGPS,
              icon: _isCapturingGps
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.location_on, size: 18),
              label: Text(
                _isCapturingGps ? 'Capturing...' : 'CAPTURE GPS LOCATION',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(0, 48),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(
                  avatar: Icon(
                    _gpsStatus.contains('Captured')
                        ? Icons.check_circle
                        : Icons.gps_off,
                    size: 16,
                    color: _gpsStatus.contains('Captured')
                        ? AppTheme.success
                        : AppTheme.textMuted,
                  ),
                  label: Text(_gpsStatus),
                  backgroundColor: _gpsStatus.contains('Captured')
                      ? AppTheme.successBg
                      : AppTheme.divider,
                ),
                if (_gpsAccuracyMeters != null)
                  Chip(
                    label: Text(
                      'Accuracy: ${_gpsAccuracyMeters!.toStringAsFixed(0)} meters',
                    ),
                    backgroundColor:
                        _gpsAccuracyMeters! > _kPoorGpsAccuracyThresholdMeters
                        ? AppTheme.warningBg
                        : AppTheme.infoBg,
                  ),
                Chip(
                  label: Text(_gpsTime),
                  backgroundColor: AppTheme.infoBg,
                ),
              ],
            ),
            if (_gpsAccuracyMeters != null &&
                _gpsAccuracyMeters! > _kPoorGpsAccuracyThresholdMeters) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GPS accuracy is currently '
                        '${_gpsAccuracyMeters!.toStringAsFixed(0)} meters. '
                        'Please move to an open area and try again.',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
