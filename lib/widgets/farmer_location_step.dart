import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/liberia_locations.dart';
import '../data/cda_cooperatives.dart';
import '../services/cooperative_registry_service.dart';
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

  // Cooperative / Group Affiliation - moved here (from Personal Info) so it
  // can be filtered by County, which is only known in this step. Backed by
  // the real CDA registry (see cda_cooperatives.dart and
  // CooperativeRegistryService), same "Other / Not Listed" fallback pattern
  // as before.
  final _cooperativeOtherNameController = TextEditingController();
  String? _cooperativeName;
  String _cooperativeSource = ''; // 'CDA_REGISTRY' | 'OTHER' | ''
  bool _loadingCooperatives = false;

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
      final existingCoopName =
          widget.initialData!['cooperativeName'] as String?;
      final existingCoopSource =
          widget.initialData!['cooperativeSource'] as String? ?? '';
      if (existingCoopName != null && existingCoopName.isNotEmpty) {
        _cooperativeName = existingCoopName;
        _cooperativeSource = existingCoopSource.isNotEmpty
            ? existingCoopSource
            : 'CDA_REGISTRY';
        if (_cooperativeSource == 'OTHER') {
          _cooperativeOtherNameController.text = existingCoopName;
        }
      }
    }
    _loadCooperativeRegistry();
    _updateData();
  }

  /// Kicks off (but doesn't block on) fetching the real CDA registry so
  /// it's ready - or at least refreshing - by the time the enumerator taps
  /// the Cooperative field. Errors are swallowed here: CooperativeRegistryService
  /// already falls back to cache/offline-seed internally, so there's
  /// nothing actionable to show the user from this background call.
  Future<void> _loadCooperativeRegistry() async {
    if (!mounted) return;
    setState(() => _loadingCooperatives = true);
    try {
      await CooperativeRegistryService.load();
    } catch (_) {
      // Already logged inside the service; nothing more to do here.
    } finally {
      if (mounted) setState(() => _loadingCooperatives = false);
    }
  }

  @override
  void dispose() {
    _countyController.dispose();
    _districtController.dispose();
    _communityController.dispose();
    _directionsController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _cooperativeOtherNameController.dispose();
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
      'cooperativeName': _cooperativeName ?? '',
      // cooperativeId intentionally no longer collected from the
      // enumerator (task spec section 2) - do not fabricate one.
      'cooperativeId': '',
      'cooperativeSource': _cooperativeSource,
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
                                      // Cooperative list is also scoped to
                                      // County (task spec: filter by
                                      // selected county) - clear any prior
                                      // CDA_REGISTRY selection that no
                                      // longer matches the new county so a
                                      // mismatched cooperative/county pair
                                      // can never be submitted. A manually
                                      // typed "Other / Not Listed" name is
                                      // left untouched since it isn't tied
                                      // to any county's registry list.
                                      if (_cooperativeSource ==
                                          'CDA_REGISTRY') {
                                        _cooperativeName = null;
                                        _cooperativeSource = '';
                                      }
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

  /// Searchable "Cooperative / Group Affiliation" picker, backed by the
  /// real CDA registry (see cda_cooperatives.dart and
  /// CooperativeRegistryService) and scoped to the already-selected County
  /// so the enumerator only ever sees that county's cooperatives instead
  /// of scrolling the full ~95-entry national list. Always includes an
  /// "Other / Not Listed" entry at the top of results so the enumerator is
  /// never blocked from registering a farmer whose cooperative isn't (yet)
  /// in the registry.
  void _showCooperativeBottomSheet() {
    final selectedCounty = _countyController.text.trim();
    final TextEditingController searchController = TextEditingController();
    List<CdaCooperative> filtered = CdaCooperatives.search(
      '',
      county: selectedCounty,
    );
    bool modalLoading = _loadingCooperatives;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterCoops(String query) {
              setModalState(() {
                filtered = CdaCooperatives.search(
                  query,
                  county: selectedCounty,
                );
              });
            }

            // Kick off (once per sheet-open) a refresh and update the
            // visible list/spinner when it resolves.
            CooperativeRegistryService.load().then((_) {
              if (!context.mounted) return;
              setModalState(() {
                modalLoading = false;
                filtered = CdaCooperatives.search(
                  searchController.text,
                  county: selectedCounty,
                );
              });
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Cooperative',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          if (modalLoading) ...[
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                          ],
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      modalLoading
                          ? 'Updating CDA registry...'
                          : (selectedCounty.isNotEmpty
                                ? 'Showing cooperatives in $selectedCounty'
                                : 'Search the CDA (Cooperative Development '
                                      'Agency) registry'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search cooperative name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filterCoops('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: AppTheme.background,
                    ),
                    onChanged: filterCoops,
                  ),
                  const SizedBox(height: 12),
                  // "Other / Not Listed" is always visible so an enumerator
                  // can pick it even before typing anything.
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.warningBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.edit_note,
                        color: AppTheme.warning,
                      ),
                      title: const Text(
                        'Other / Not Listed',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Enter the cooperative name manually',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _promptOtherCooperativeName();
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
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
                                Text(
                                  selectedCounty.isNotEmpty
                                      ? 'No cooperatives found in '
                                            '$selectedCounty.\nUse "Other / '
                                            'Not Listed" above.'
                                      : 'No cooperatives found.\nUse '
                                            '"Other / Not Listed" above.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final coop = filtered[index];
                              final isSelected =
                                  _cooperativeSource == 'CDA_REGISTRY' &&
                                  _cooperativeName == coop.name;
                              return ListTile(
                                title: Text(coop.name),
                                subtitle: coop.county != null
                                    ? Text(coop.county!)
                                    : null,
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
                                    _cooperativeSource = 'CDA_REGISTRY';
                                    _cooperativeName = coop.name;
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

  Future<void> _promptOtherCooperativeName() async {
    _cooperativeOtherNameController.text =
        _cooperativeSource == 'OTHER' ? (_cooperativeName ?? '') : '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Enter Cooperative Name'),
          content: TextField(
            controller: _cooperativeOtherNameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g., Bopolu Farmers Cooperative',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                ctx,
                _cooperativeOtherNameController.text.trim(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _cooperativeSource = 'OTHER';
        _cooperativeName = result;
        _updateData();
      });
    }
  }

  void _clearCooperative() {
    setState(() {
      _cooperativeSource = '';
      _cooperativeName = null;
      _cooperativeOtherNameController.clear();
      _updateData();
    });
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
            // -----------------------------------------------------------
            // Cooperative / Group Affiliation - moved here (from Personal
            // Info) so it can be scoped to the County just selected above,
            // instead of showing the full ~95-entry national CDA registry.
            // -----------------------------------------------------------
            const SizedBox(height: 24),
            const Text(
              'Group / Cooperative Affiliation (Optional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasCounty
                  ? 'Showing cooperatives registered in '
                        '${_countyController.text.trim()}'
                  : 'Select a county above to see cooperatives in that area',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _showCooperativeBottomSheet,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Cooperative',
                  hintText: 'Tap to search CDA registry',
                  suffixIcon:
                      (_cooperativeName != null &&
                          _cooperativeName!.isNotEmpty)
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearCooperative,
                        )
                      : const Icon(Icons.search),
                ),
                child: Text(
                  (_cooperativeName != null && _cooperativeName!.isNotEmpty)
                      ? _cooperativeName!
                      : 'Not selected',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        (_cooperativeName != null &&
                            _cooperativeName!.isNotEmpty)
                        ? Colors.black87
                        : AppTheme.textMuted,
                  ),
                ),
              ),
            ),
            if (_cooperativeSource == 'OTHER' &&
                _cooperativeName != null &&
                _cooperativeName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Not found in CDA registry - flagged for later review.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ],

            // -----------------------------------------------------------
            // Farmer's Residential GPS - explicitly the farmer's HOME /
            // RESIDENCE location, which may be some distance from the farm
            // itself (captured separately later, in the Mapping step, via
            // the farm boundary polygon). Relabeled from the previous
            // generic "CAPTURE GPS LOCATION" so this distinction is clear
            // to the enumerator in the field.
            // -----------------------------------------------------------
            const SizedBox(height: 24),
            const Text(
              "Farmer's Residential Location",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Capture the GPS where the farmer LIVES (their home/residence) '
              '- this may be different from the farm location, which is '
              'mapped separately in the Mapping step.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
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
                  : const Icon(Icons.home_work_outlined, size: 18),
              label: Text(
                _isCapturingGps
                    ? 'Capturing...'
                    : "CAPTURE FARMER'S RESIDENTIAL GPS",
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
                labelText: 'Residential Latitude',
                hintText: '—',
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lngController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Residential Longitude',
                hintText: '—',
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _directionsController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Directions to Residence (optional)',
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
