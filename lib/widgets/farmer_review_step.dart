import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import '../theme/app_theme.dart';

class FarmerReviewStep extends StatelessWidget {
  final Map<String, dynamic> formData;

  const FarmerReviewStep({super.key, required this.formData});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Review all information before submitting',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please verify that all details are correct. You can go back to edit any section.',
            style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),

          // Personal Information Section
          _buildSection(
            context,
            title: 'Personal Information',
            icon: Icons.person,
            items: [
              _buildItem('Full Name', formData['fullName']),
              _buildItem('Gender', formData['gender']),
              _buildItem('Date of Birth', formData['dob']),
              _buildItem('Phone Number', formData['phone']),
              _buildItem('Nationality', formData['nationality']),
              _buildItem('National ID', formData['nationalId'], optional: true),
              _buildItem('Email', formData['email'], optional: true),
              _buildItem(
                'Cooperative Name',
                formData['cooperativeName'],
                optional: true,
              ),
              _buildItem(
                'Cooperative ID',
                formData['cooperativeId'],
                optional: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Location Information Section
          _buildSection(
            context,
            title: 'Location & GPS',
            icon: Icons.location_on,
            items: [
              _buildItem('County', formData['county']),
              _buildItem('District', formData['district'], optional: true),
              _buildItem('Community/Town/Village', formData['community']),
              _buildItem('Inspector Name', formData['inspectorName']),
              _buildItem(
                'Enumerator / Inspector ID',
                formData['enumeratorId'],
                optional: true,
              ),
              _buildItem('Latitude', formData['lat']),
              _buildItem('Longitude', formData['lng']),
              _buildItem('Directions', formData['directions'], optional: true),
            ],
          ),

          const SizedBox(height: 16),

          // Farm Details Section
          _buildSection(
            context,
            title: 'Farm Details',
            icon: Icons.agriculture,
            items: [
              _buildItem('Farm Name', formData['farmName']),
              _buildItem('Primary Crop', formData['crop']),
              _buildItem('Ownership Type', formData['ownership']),
              _buildItem(
                'Registration Status',
                formData['regStatus'],
                optional: true,
              ),
              _buildItem(
                'Farm Size',
                formData['farmSizeManual'],
                optional: true,
              ),
              _buildItem('Unit', formData['farmUnitManual'], optional: true),
              _buildItem('Farm Notes', formData['farmNotes'], optional: true),
              _buildItem(
                'Number of Trees',
                formData['numberOfTrees'],
                optional: true,
              ),
              _buildItem(
                'Years in Cultivation',
                formData['yearsInCultivation'],
                optional: true,
              ),
              _buildItem(
                'Harvest Season',
                formData['harvestSeason'],
                optional: true,
              ),
              _buildItem(
                'Average Yield',
                formData['averageYield'],
                optional: true,
              ),
              _buildItem('Buyers', formData['buyers'], optional: true),
              _buildItem(
                'Farm Address',
                formData['farmAddress'],
                optional: true,
              ),
              _buildStatusItem(
                'Uses Fertilizers / Chemicals',
                formData['useChemicals'] == true,
              ),
              _buildStatusItem(
                'Access to Extension Services',
                formData['extensionServices'] == true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Boundary/Mapping Section
          _buildSection(
            context,
            title: 'Farm Boundary',
            icon: Icons.map,
            items: [
              _buildItem('Area (Hectares)', formData['areaHa']),
              _buildItem('Area (Acres)', formData['areaAc']),
              _buildStatusItem(
                'Boundary Mapped',
                formData['boundaryJson'] != null,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Attachments Section
          _buildAttachmentsSection(context),

          const SizedBox(height: 24),

          // Debug JSON Section (Collapsible)
          ExpansionTile(
            title: const Text(
              'View Raw Data (for debugging)',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            leading: const Icon(Icons.code, size: 20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  color: AppTheme.background,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'JSON Payload',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Copy to clipboard',
                          onPressed: () {
                            final jsonString = const JsonEncoder.withIndent(
                              '  ',
                            ).convert(formData);
                            Clipboard.setData(ClipboardData(text: jsonString));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payload copied to clipboard'),
                                duration: Duration(seconds: 2),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(formData),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.paleGreen,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(String label, dynamic value, {bool optional = false}) {
    final displayValue = value?.toString().trim() ?? '';
    final isEmpty = displayValue.isEmpty || displayValue == 'null';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              isEmpty ? (optional ? '—' : 'Not provided') : displayValue,
              style: TextStyle(
                fontSize: 14,
                color: isEmpty ? AppTheme.textMuted : AppTheme.textPrimary,
                fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, bool isPresent, {String? extraInfo}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  isPresent ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: isPresent ? AppTheme.success : AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPresent ? (extraInfo ?? 'Uploaded') : 'Not uploaded',
                    style: TextStyle(
                      fontSize: 14,
                      color: isPresent ? AppTheme.textPrimary : AppTheme.textMuted,
                      fontStyle: isPresent
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.paleGreen,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file,
                  size: 20,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Attachments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImagePreview(
                  context,
                  'Farmer Photo',
                  formData['farmerPhotoPath'],
                ),
                const SizedBox(height: 12),
                _buildImagePreview(
                  context,
                  'National ID Photo',
                  formData['nationalIdPath'],
                ),
                const SizedBox(height: 12),
                _buildImagePreview(
                  context,
                  'Farm Selfie',
                  formData['farmSelfiePath'],
                ),
                const SizedBox(height: 12),
                _buildImagePreview(
                  context,
                  'Farmer Signature',
                  formData['signaturePath'],
                ),
                const SizedBox(height: 12),
                _buildMultipleImagesPreview(
                  context,
                  'Farm Photos',
                  formData['farmPhotosPaths'],
                ),
                const SizedBox(height: 12),
                _buildStatusItem('Consent Given', formData['consent'] == true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(
    BuildContext context,
    String label,
    dynamic imagePath,
  ) {
    final hasImage = imagePath != null && imagePath.toString().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasImage ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: hasImage ? AppTheme.success : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        if (hasImage) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showImageDialog(context, imagePath.toString(), label),
            child: Container(
              height: 120,
              width: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: AppTheme.border),
                image: DecorationImage(
                  image: FileImage(File(imagePath.toString())),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  color: Colors.black.withValues(alpha: 0.0),
                ),
                child: const Center(
                  child: Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 32,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          const Text(
            'Not uploaded',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMultipleImagesPreview(
    BuildContext context,
    String label,
    dynamic imagePaths,
  ) {
    final hasImages =
        imagePaths != null && imagePaths is List && imagePaths.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasImages ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: hasImages ? AppTheme.success : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            if (hasImages) ...[
              const SizedBox(width: 8),
              Text(
                '(${imagePaths.length} photo(s))',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
        if (hasImages) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: imagePaths.map<Widget>((path) {
              return GestureDetector(
                onTap: () => _showImageDialog(context, path.toString(), label),
                child: Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: AppTheme.border),
                    image: DecorationImage(
                      image: FileImage(File(path.toString())),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      color: Colors.black.withValues(alpha: 0.0),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                        size: 24,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ] else ...[
          const SizedBox(height: 4),
          const Text(
            'Not uploaded',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  void _showImageDialog(BuildContext context, String imagePath, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4,
                child: Image.file(File(imagePath), fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
