import 'package:flutter/material.dart';

class FarmerFarmDetailsStep extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataChanged;
  final Map<String, dynamic>? initialData;

  const FarmerFarmDetailsStep({
    super.key,
    required this.onDataChanged,
    this.initialData,
  });

  @override
  State<FarmerFarmDetailsStep> createState() => _FarmerFarmDetailsStepState();
}

class _FarmerFarmDetailsStepState extends State<FarmerFarmDetailsStep> {
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _cropController = TextEditingController();
  final _ownershipController = TextEditingController();
  final _regStatusController = TextEditingController();
  final _farmSizeManualController = TextEditingController();
  final _farmUnitManualController = TextEditingController();
  final _farmNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _farmNameController.text = widget.initialData!['farmName'] ?? '';
      _cropController.text = widget.initialData!['crop'] ?? '';
      _ownershipController.text = widget.initialData!['ownership'] ?? '';
      _regStatusController.text = widget.initialData!['regStatus'] ?? '';
      if (widget.initialData!['farmSizeManual'] != null) {
        _farmSizeManualController.text = widget.initialData!['farmSizeManual']
            .toString();
      }
      _farmUnitManualController.text =
          widget.initialData!['farmUnitManual'] ?? 'hectares';
      _farmNotesController.text = widget.initialData!['farmNotes'] ?? '';
    }
    _updateData();
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _cropController.dispose();
    _ownershipController.dispose();
    _regStatusController.dispose();
    _farmSizeManualController.dispose();
    _farmUnitManualController.dispose();
    _farmNotesController.dispose();
    super.dispose();
  }

  void _updateData() {
    widget.onDataChanged({
      'farmName': _farmNameController.text.trim(),
      'crop': _cropController.text.trim(),
      'ownership': _ownershipController.text.trim(),
      'regStatus': _regStatusController.text.trim(),
      'farmSizeManual': _farmSizeManualController.text.trim().isNotEmpty
          ? _farmSizeManualController.text.trim()
          : null,
      'farmUnitManual': _farmUnitManualController.text.trim(),
      'farmNotes': _farmNotesController.text.trim(),
    });
  }

  String generateFarmName(Map<String, dynamic>? allData) {
    if (allData == null) return 'Unnamed Farm';

    final farmerName = allData['fullName']?.toString().trim() ?? '';
    final crop = _cropController.text.trim();
    final community = allData['community']?.toString().trim() ?? '';

    final parts = <String>[];
    if (farmerName.isNotEmpty) {
      // Get first name only
      parts.add(farmerName.split(' ').first);
    }
    if (crop.isNotEmpty) parts.add(crop);
    if (community.isNotEmpty) parts.add(community);

    return parts.isEmpty ? 'Unnamed Farm' : '${parts.join(' ')} Farm';
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
              controller: _farmNameController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Farm Name (Optional)',
                hintText: 'e.g., Johnson Cocoa Farm',
                helperText:
                    'Leave empty to auto-generate from farmer name + crop + community',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _cropController.text.isEmpty
                  ? null
                  : _cropController.text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'Primary Crop *'),
              items: const [
                DropdownMenuItem(
                  value: 'Cocoa',
                  child: Text('Cocoa', style: TextStyle(color: Colors.black87)),
                ),
                DropdownMenuItem(
                  value: 'Coffee',
                  child: Text(
                    'Coffee',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Oil Palm',
                  child: Text(
                    'Oil Palm',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Rubber',
                  child: Text(
                    'Rubber',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Cassava',
                  child: Text(
                    'Cassava',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Vegetables',
                  child: Text(
                    'Vegetables',
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
                  _cropController.text = value ?? '';
                  _updateData();
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Primary crop is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _ownershipController.text.isEmpty
                  ? null
                  : _ownershipController.text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'Ownership Type *'),
              items: const [
                DropdownMenuItem(
                  value: 'Owned',
                  child: Text('Owned', style: TextStyle(color: Colors.black87)),
                ),
                DropdownMenuItem(
                  value: 'Rented',
                  child: Text(
                    'Rented',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Family Inherited',
                  child: Text(
                    'Family Inherited',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Communal',
                  child: Text(
                    'Communal',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _ownershipController.text = value ?? '';
                  _updateData();
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ownership type is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _regStatusController.text.isEmpty
                  ? null
                  : _regStatusController.text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(
                labelText: 'Farm Registration Status',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Registered',
                  child: Text(
                    'Registered',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Not Registered',
                  child: Text(
                    'Not Registered',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _regStatusController.text = value ?? '';
                  _updateData();
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _farmSizeManualController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Farm Size (manual estimate)',
                hintText: 'e.g., 3.2',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _farmUnitManualController.text.isEmpty
                  ? 'hectares'
                  : _farmUnitManualController.text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: Colors.black87,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: const [
                DropdownMenuItem(
                  value: 'hectares',
                  child: Text(
                    'Hectares',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
                DropdownMenuItem(
                  value: 'acres',
                  child: Text('Acres', style: TextStyle(color: Colors.black87)),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _farmUnitManualController.text = value ?? 'hectares';
                  _updateData();
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _farmNotesController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Any special notes about the farm...',
              ),
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }
}
