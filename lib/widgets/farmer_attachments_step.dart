import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class FarmerAttachmentsStep extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataChanged;
  final Map<String, dynamic>? initialData;

  const FarmerAttachmentsStep({
    super.key,
    required this.onDataChanged,
    this.initialData,
  });

  @override
  State<FarmerAttachmentsStep> createState() => _FarmerAttachmentsStepState();
}

/// EUDR due-diligence compliance documents collected alongside the farmer's
/// photos - these prove land rights/affiliation, distinct from the basic
/// "National ID photo" already captured above. Backend enum values live in
/// FarmDocument.ts's DocumentType - keep the label strings below IDENTICAL
/// to those enum values, since they're sent as-is in complianceDocTypes.
const List<String> kComplianceDocumentTypes = [
  'National ID / Identification Document',
  'Land Deed / Land Ownership Document',
  'Lease / Land-Use Agreement',
  'Customary or Community Land Authorization',
  'Cooperative/Association Membership Document',
];

class _FarmerAttachmentsStepState extends State<FarmerAttachmentsStep> {
  final ImagePicker _picker = ImagePicker();
  String? _nationalIdPath;
  String? _farmSelfiePath;
  String? _signaturePath;
  List<String> _farmPhotosPaths = [];
  bool _consent = false;
  // Compliance document type -> local file path. Only types the inspector
  // actually picked a file for are present as keys.
  final Map<String, String> _complianceDocs = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nationalIdPath = widget.initialData!['nationalIdPath'];
      _farmSelfiePath = widget.initialData!['farmSelfiePath'];
      _signaturePath = widget.initialData!['signaturePath'];
      _farmPhotosPaths = List<String>.from(
        widget.initialData!['farmPhotosPaths'] ?? [],
      );
      _consent = widget.initialData!['consent'] ?? false;
      final existingDocs = widget.initialData!['complianceDocuments'];
      if (existingDocs is List) {
        for (final entry in existingDocs) {
          if (entry is Map && entry['type'] != null && entry['path'] != null) {
            _complianceDocs[entry['type'].toString()] = entry['path']
                .toString();
          }
        }
      }
    }
    _updateData();
  }

  void _updateData() {
    widget.onDataChanged({
      'nationalIdPath': _nationalIdPath,
      'farmSelfiePath': _farmSelfiePath,
      'signaturePath': _signaturePath,
      'farmPhotosPaths': _farmPhotosPaths,
      'consent': _consent,
      'complianceDocuments': _complianceDocs.entries
          .map((e) => {'type': e.key, 'path': e.value})
          .toList(),
    });
  }

  Future<void> _pickComplianceDoc(String type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _complianceDocs[type] = result.files.single.path!;
          _updateData();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking document: $e')));
    }
  }

  void _removeComplianceDoc(String type) {
    setState(() {
      _complianceDocs.remove(type);
      _updateData();
    });
  }

  Future<void> _pickNationalId() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _nationalIdPath = result.files.single.path!;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    }
  }

  Future<void> _pickFarmSelfie() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _farmSelfiePath = image.path;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _pickFarmSelfieFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _farmSelfiePath = image.path;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _pickFarmPhotos() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(imageQuality: 85);
      if (images.isNotEmpty) {
        setState(() {
          _farmPhotosPaths.addAll(images.map((img) => img.path));
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking images: $e')));
    }
  }

  Future<void> _pickSignature() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _signaturePath = image.path;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _pickSignatureFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _signaturePath = result.files.single.path!;
          _updateData();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    }
  }

  void _removeFarmPhoto(int index) {
    setState(() {
      _farmPhotosPaths.removeAt(index);
      _updateData();
    });
  }

  bool validate() {
    if (!_consent) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Upload National ID / Proof (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _pickNationalId,
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose File'),
          ),
          if (_nationalIdPath != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nationalIdPath!.split('/').last,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _nationalIdPath = null;
                        _updateData();
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.folder_copy_outlined,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compliance Documents (recommended)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Upload a photo or PDF of any documents the farmer '
                        'has available. Not all documents will apply to '
                        'every farmer - upload whichever are relevant.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...kComplianceDocumentTypes.map((type) {
            final path = _complianceDocs[type];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: path != null
                      ? Colors.green.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: path != null
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      path != null
                          ? Icons.check_circle
                          : Icons.insert_drive_file_outlined,
                      color: path != null ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                          if (path != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                path.split('/').last,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (path != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeComplianceDoc(type),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => _pickComplianceDoc(type),
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text(
                          'Upload',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          const Text(
            'Upload Farmer on Farm Photo (recommended)',
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
                  onPressed: _pickFarmSelfieFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickFarmSelfie,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          if (_farmSelfiePath != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_farmSelfiePath!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: () {
                        setState(() {
                          _farmSelfiePath = null;
                          _updateData();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Farmer Signature (recommended)',
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
                  onPressed: _pickSignatureFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickSignature,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          if (_signaturePath != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.white,
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_signaturePath!),
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: () {
                        setState(() {
                          _signaturePath = null;
                          _updateData();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Upload Farm Photos (optional, multiple)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _pickFarmPhotos,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Add Photos'),
          ),
          if (_farmPhotosPaths.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_farmPhotosPaths.length, (index) {
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_farmPhotosPaths[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeFarmPhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _consent,
            onChanged: (value) {
              setState(() {
                _consent = value ?? false;
                _updateData();
              });
            },
            title: const Text(
              'Farmer agrees to data capture and verification *',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          const Text(
            'Tip: Evidence photos are very important for verification and audits.',
            style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }
}
