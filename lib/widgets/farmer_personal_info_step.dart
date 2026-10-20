import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../data/liberia_locations.dart';
import '../theme/app_theme.dart';
import 'media_capture_field.dart';

class FarmerPersonalInfoStep extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataChanged;
  final Map<String, dynamic>? initialData;

  const FarmerPersonalInfoStep({
    super.key,
    required this.onDataChanged,
    this.initialData,
  });

  @override
  State<FarmerPersonalInfoStep> createState() => _FarmerPersonalInfoStepState();
}

class _FarmerPersonalInfoStepState extends State<FarmerPersonalInfoStep> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _genderController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _idTypeOtherController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _countyOfOriginController = TextEditingController();
  String? _idType;

  // Task spec section 1: ID Type must be one of these four options (no
  // free-form "Voting ID" etc. anymore - simplified to match the standard
  // set of IDs the CDA/LACRA actually accept).
  static const List<String> _idTypeOptions = [
    'National ID',
    'Passport',
    "Driver's License",
    'Other',
  ];

  String? _photoPath;
  String? _idDocumentPath;
  DateTime? _selectedDate;

  // NOTE: Cooperative / Group Affiliation used to live here but has moved
  // to FarmerLocationStep (Location & GPS step), since it needs to be
  // filtered by County - which is only known in that later step. See
  // farmer_location_step.dart for the current implementation. The
  // 'cooperativeName'/'cooperativeId'/'cooperativeSource' keys are still
  // read from/written to the same shared _formData map, so no change was
  // needed to FarmerRegistrationModel or the backend.

  // Complete list of countries
  static const List<String> _allCountries = [
    'Afghan',
    'Albanian',
    'Algerian',
    'Andorran',
    'Angolan',
    'Antiguans',
    'Argentine',
    'Armenian',
    'Australian',
    'Austrian',
    'Azerbaijani',
    'Bahamian',
    'Bahraini',
    'Bangladeshi',
    'Barbadian',
    'Belarusian',
    'Belgian',
    'Belizean',
    'Beninese',
    'Bhutanese',
    'Bolivian',
    'Bosnian',
    'Botswanan',
    'Brazilian',
    'British',
    'Bruneian',
    'Bulgarian',
    'Burkinabe',
    'Burmese',
    'Burundian',
    'Cambodian',
    'Cameroonian',
    'Canadian',
    'Cape Verdean',
    'Central African',
    'Chadian',
    'Chilean',
    'Chinese',
    'Colombian',
    'Comoran',
    'Congolese',
    'Costa Rican',
    'Croatian',
    'Cuban',
    'Cypriot',
    'Czech',
    'Danish',
    'Djiboutian',
    'Dominican',
    'Dutch',
    'East Timorese',
    'Ecuadorean',
    'Egyptian',
    'Emirati',
    'Equatorial Guinean',
    'Eritrean',
    'Estonian',
    'Ethiopian',
    'Fijian',
    'Filipino',
    'Finnish',
    'French',
    'Gabonese',
    'Gambian',
    'Georgian',
    'German',
    'Ghanaian',
    'Greek',
    'Grenadian',
    'Guatemalan',
    'Guinean',
    'Guinea-Bissauan',
    'Guyanese',
    'Haitian',
    'Honduran',
    'Hungarian',
    'Icelandic',
    'Indian',
    'Indonesian',
    'Iranian',
    'Iraqi',
    'Irish',
    'Israeli',
    'Italian',
    'Ivorian',
    'Jamaican',
    'Japanese',
    'Jordanian',
    'Kazakhstani',
    'Kenyan',
    'Kittian and Nevisian',
    'Kuwaiti',
    'Kyrgyz',
    'Laotian',
    'Latvian',
    'Lebanese',
    'Liberian',
    'Libyan',
    'Liechtensteiner',
    'Lithuanian',
    'Luxembourger',
    'Macedonian',
    'Malagasy',
    'Malawian',
    'Malaysian',
    'Maldivian',
    'Malian',
    'Maltese',
    'Marshallese',
    'Mauritanian',
    'Mauritian',
    'Mexican',
    'Micronesian',
    'Moldovan',
    'Monacan',
    'Mongolian',
    'Montenegrin',
    'Moroccan',
    'Mozambican',
    'Namibian',
    'Nauruan',
    'Nepalese',
    'New Zealander',
    'Nicaraguan',
    'Nigerian',
    'Nigerien',
    'North Korean',
    'Northern Irish',
    'Norwegian',
    'Omani',
    'Pakistani',
    'Palauan',
    'Panamanian',
    'Papua New Guinean',
    'Paraguayan',
    'Peruvian',
    'Polish',
    'Portuguese',
    'Qatari',
    'Romanian',
    'Russian',
    'Rwandan',
    'Saint Lucian',
    'Salvadoran',
    'Samoan',
    'San Marinese',
    'Sao Tomean',
    'Saudi',
    'Senegalese',
    'Serbian',
    'Seychellois',
    'Sierra Leonean',
    'Singaporean',
    'Slovak',
    'Slovenian',
    'Solomon Islander',
    'Somali',
    'South African',
    'South Korean',
    'South Sudanese',
    'Spanish',
    'Sri Lankan',
    'Sudanese',
    'Surinamer',
    'Swazi',
    'Swedish',
    'Swiss',
    'Syrian',
    'Taiwanese',
    'Tajik',
    'Tanzanian',
    'Thai',
    'Togolese',
    'Tongan',
    'Trinidadian or Tobagonian',
    'Tunisian',
    'Turkish',
    'Tuvaluan',
    'Ugandan',
    'Ukrainian',
    'Uruguayan',
    'Uzbekistani',
    'Vanuatuan',
    'Vatican',
    'Venezuelan',
    'Vietnamese',
    'Yemenite',
    'Zambian',
    'Zimbabwean',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _fullNameController.text = widget.initialData!['fullName'] ?? '';
      _genderController.text = widget.initialData!['gender'] ?? '';
      final dobStr = widget.initialData!['dob'] ?? '';
      if (dobStr.isNotEmpty) {
        try {
          _selectedDate = DateFormat('yyyy-MM-dd').parse(dobStr);
          _dobController.text = DateFormat('yyyy-MM-dd').format(_selectedDate!);
        } catch (e) {
          _dobController.text = dobStr;
        }
      }
      // Extract just the digits if phone has +231 prefix
      final phone = widget.initialData!['phone'] ?? '';
      if (phone.startsWith('+231')) {
        _phoneController.text = phone.substring(4);
      } else {
        _phoneController.text = phone;
      }
      final existingNationality = widget.initialData!['nationality'] as String?;
      // Default to Liberian for a brand-new form (most farmers registered
      // are Liberian) - only applied when nothing has been set yet, so an
      // existing draft/pending item that was already filled out (including
      // one where the enumerator deliberately chose a different
      // nationality) is never silently overwritten.
      _nationalityController.text =
          (existingNationality == null || existingNationality.isEmpty)
          ? 'Liberian'
          : existingNationality;
      _countyOfOriginController.text =
          widget.initialData!['countyOfOrigin'] ?? '';
      final idTypeValue = widget.initialData!['idType'] as String?;
      // Backwards-compat: older saved drafts/pending items may still carry
      // the previous option labels (e.g. "National ID card", "Others") -
      // map those onto the new 4-option set so existing data still shows
      // correctly instead of falling back to "no selection".
      _idType = _normalizeIdType(idTypeValue);
      _idTypeOtherController.text = widget.initialData!['idTypeOther'] ?? '';
      _nationalIdController.text = widget.initialData!['nationalId'] ?? '';
      _emailController.text = widget.initialData!['email'] ?? '';
      _photoPath = widget.initialData!['farmerPhotoPath'];
      _idDocumentPath = widget.initialData!['nationalIdPath'];
    }
    _updateData();
  }

  String? _normalizeIdType(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (_idTypeOptions.contains(raw)) return raw;
    switch (raw) {
      case 'National ID card':
        return 'National ID';
      case 'Driver License':
        return "Driver's License";
      case 'Voting ID':
        return 'Other';
      case 'Others':
        return 'Other';
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _genderController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _nationalityController.dispose();
    _idTypeOtherController.dispose();
    _nationalIdController.dispose();
    _emailController.dispose();
    _countyOfOriginController.dispose();
    super.dispose();
  }

  void _updateData() {
    // Add +231 prefix to phone if digits are entered
    final phoneDigits = _phoneController.text.trim();
    final phoneWithPrefix = phoneDigits.isNotEmpty ? '+231$phoneDigits' : '';

    widget.onDataChanged({
      'fullName': _fullNameController.text.trim(),
      'gender': _genderController.text.trim(),
      'dob': _selectedDate != null
          ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
          : _dobController.text.trim(),
      'phone': phoneWithPrefix,
      'nationality': _nationalityController.text.trim(),
      'countyOfOrigin': _countyOfOriginController.text.trim(),
      'idType': _idType ?? '',
      'idTypeOther': _idType == 'Other'
          ? _idTypeOtherController.text.trim()
          : '',
      'nationalId': _nationalIdController.text.trim(),
      'nationalIdPath': _idDocumentPath,
      'email': _emailController.text.trim(),
      // NOTE: cooperativeName/cooperativeId/cooperativeSource are no longer
      // emitted from this step - they're now owned by FarmerLocationStep
      // (see that file's _updateData()). Deliberately NOT including empty
      // placeholder values for these keys here, since _formData.addAll()
      // in FarmerRegistryScreen would otherwise let this step's (now
      // irrelevant) merge clobber whatever FarmerLocationStep already set,
      // depending on which step last rebuilt.
      'farmerPhotoPath': _photoPath,
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDate ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select Date of Birth',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryGreen,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
        _updateData();
      });
    }
  }

  void _showNationalityBottomSheet() {
    final TextEditingController searchController = TextEditingController();
    List<String> filteredCountries = List.from(_allCountries);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterCountries(String query) {
              setModalState(() {
                if (query.isEmpty) {
                  filteredCountries = List.from(_allCountries);
                } else {
                  filteredCountries = _allCountries
                      .where(
                        (country) =>
                            country.toLowerCase().contains(query.toLowerCase()),
                      )
                      .toList();
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Nationality',
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
                      hintText: 'Search country...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filterCountries('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: AppTheme.background,
                    ),
                    onChanged: filterCountries,
                  ),
                  const SizedBox(height: 16),

                  // Country list
                  Expanded(
                    child: filteredCountries.isEmpty
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
                                  'No countries found',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredCountries.length,
                            itemBuilder: (context, index) {
                              final nationality = filteredCountries[index];
                              final isSelected =
                                  _nationalityController.text == nationality;
                              return ListTile(
                                title: Text(nationality),
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
                                    _nationalityController.text = nationality;
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

  void _showCountyOfOriginBottomSheet() {
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select County of Origin',
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
                  Expanded(
                    child: filteredCounties.isEmpty
                        ? const Center(
                            child: Text(
                              'No counties found',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredCounties.length,
                            itemBuilder: (context, index) {
                              final county = filteredCounties[index];
                              final isSelected =
                                  _countyOfOriginController.text == county;
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
                                    _countyOfOriginController.text = county;
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

  bool validate() {
    return _formKey.currentState?.validate() ?? false;
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
              controller: _fullNameController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Farmer Full Name *',
                hintText: 'e.g., Mary T. Kamara',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Full name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _genderController.text.isEmpty
                  ? null
                  : _genderController.text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'Gender *'),
              items: const [
                DropdownMenuItem(
                  value: 'Male',
                  child: Text('Male', style: TextStyle(color: Colors.black87)),
                ),
                DropdownMenuItem(
                  value: 'Female',
                  child: Text(
                    'Female',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Other',
                  child: Text('Other', style: TextStyle(color: Colors.black87)),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _genderController.text = value ?? '';
                  _updateData();
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Gender is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dobController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Date of Birth / Age',
                hintText: 'Tap to select date',
                suffixIcon: const Icon(Icons.calendar_today),
              ),
              onTap: _selectDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                hintText: 'Enter 9 digits',
                prefixText: '+231 ',
                prefixStyle: TextStyle(fontSize: 14, color: Colors.black87),
                counterText: '',
              ),
              keyboardType: TextInputType.number,
              maxLength: 9,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Phone number is required';
                }
                final digits = value.trim();
                // Check exactly 9 digits
                if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
                  return 'Phone must be exactly 9 digits';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nationalityController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Country',
                hintText: 'Tap to select',
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              onTap: _showNationalityBottomSheet,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _countyOfOriginController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'County of Origin',
                hintText: 'Where the farmer originally comes from',
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              onTap: _showCountyOfOriginBottomSheet,
            ),

            // -----------------------------------------------------------
            // Farmer ID Information (task spec section 1)
            // -----------------------------------------------------------
            const SizedBox(height: 24),
            const Text(
              'Farmer ID Information',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _idType,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'ID Type *'),
              items: _idTypeOptions
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(
                        option,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _idType = value;
                  if (_idType != 'Other') {
                    _idTypeOtherController.clear();
                  }
                  _updateData();
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select the ID type';
                }
                return null;
              },
            ),
            if (_idType == 'Other') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _idTypeOtherController,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Please specify ID type *',
                  hintText: 'e.g., Refugee ID Card',
                ),
                validator: (value) {
                  if (_idType == 'Other' &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Please specify the ID type';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nationalIdController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'ID Number *',
                hintText: 'Enter the number shown on the selected ID',
              ),
              // Required whenever an ID Type has been chosen - this is the
              // "required ID Number field tied to ID Type" from task spec
              // section 1. If no ID type is set yet, don't nag the
              // enumerator until they pick one.
              validator: (value) {
                if (_idType != null &&
                    _idType!.isNotEmpty &&
                    (value == null || value.trim().isEmpty)) {
                  return 'ID Number is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            MediaCaptureField(
              label: 'ID Document *',
              helperText:
                  'Take a photo of the ID or upload a scan (JPG/PNG/PDF, max 2MB).',
              kind: MediaCaptureKind.document,
              allowPdf: true,
              required: true,
              initialPath: _idDocumentPath,
              onChanged: (path) {
                setState(() {
                  _idDocumentPath = path;
                  _updateData();
                });
              },
            ),

            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Email (Optional)',
                hintText: 'email@example.com',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                }
                return null;
              },
            ),

            // -----------------------------------------------------------
            // Farmer Photo (task spec section 3) - official profile photo
            // -----------------------------------------------------------
            const SizedBox(height: 24),
            MediaCaptureField(
              label: 'Farmer Photo *',
              helperText:
                  'Portrait photo used as the farmer\'s official profile picture.',
              kind: MediaCaptureKind.profilePhoto,
              initialPath: _photoPath,
              required: true,
              onChanged: (path) {
                setState(() {
                  _photoPath = path;
                  _updateData();
                });
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
