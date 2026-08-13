import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';

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
  String? _idType;

  static const List<String> _idTypeOptions = [
    'Driver License',
    'National ID card',
    'Passport',
    'Voting ID',
    'Others',
  ];
  final ImagePicker _picker = ImagePicker();
  String? _photoPath;
  DateTime? _selectedDate;

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
      _nationalityController.text = widget.initialData!['nationality'] ?? '';
      final idTypeValue = widget.initialData!['idType'] as String?;
      _idType = (idTypeValue != null && _idTypeOptions.contains(idTypeValue))
          ? idTypeValue
          : null;
      _idTypeOtherController.text = widget.initialData!['idTypeOther'] ?? '';
      _nationalIdController.text = widget.initialData!['nationalId'] ?? '';
      _emailController.text = widget.initialData!['email'] ?? '';
      _photoPath = widget.initialData!['farmerPhotoPath'];
    }
    _updateData();
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
      'idType': _idType ?? '',
      'idTypeOther': _idType == 'Others'
          ? _idTypeOtherController.text.trim()
          : '',
      'nationalId': _nationalIdController.text.trim(),
      'email': _emailController.text.trim(),
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
              primary: Color(0xFF4CAF50),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
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
                      fillColor: Colors.grey.shade100,
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
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No countries found',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
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
                                        color: Color(0xFF4CAF50),
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor: const Color(
                                  0xFF4CAF50,
                                ).withOpacity(0.1),
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

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _photoPath = image.path;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _photoPath = image.path;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
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
                labelText: 'Nationality',
                hintText: 'Tap to select',
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              onTap: _showNationalityBottomSheet,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _idType,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'Type of ID'),
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
                  if (_idType != 'Others') {
                    _idTypeOtherController.clear();
                  }
                  _updateData();
                });
              },
            ),
            if (_idType == 'Others') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _idTypeOtherController,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Please specify ID type',
                  hintText: 'e.g., Refugee ID Card',
                ),
                validator: (value) {
                  if (_idType == 'Others' &&
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
                labelText: 'ID Card Number / Value',
                hintText: 'Enter the ID number shown on the selected ID',
              ),
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
            const SizedBox(height: 24),
            const Text(
              'Farmer Photo (upload/capture)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text(
                      'Choose from Gallery',
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text(
                      'Take Photo',
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
              ],
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 16),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_photoPath!), fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Tip: On a phone/tablet, the camera option will appear automatically for photo capture.',
              style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
          ],
        ),
      ),
    );
  }
}
