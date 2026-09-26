import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../services/media_optimizer_service.dart';
import '../theme/app_theme.dart';

/// What kind of media this field is capturing. Drives which
/// [MediaOptimizerService] preset (and crop aspect ratio) is used.
enum MediaCaptureKind {
  /// The official farmer profile photo. Portrait, 600x800, 200-500KB target.
  profilePhoto,

  /// An ID document, compliance document image, or any other document
  /// photo/scan. Free aspect ratio, 500KB-1.5MB target, must stay legible.
  document,
}

/// Result handed back to the caller once a file has been picked/captured,
/// (optionally) cropped, and compressed.
class MediaCaptureResult {
  final String path;
  final int originalBytes;
  final int finalBytes;
  final bool wasCompressed;

  const MediaCaptureResult({
    required this.path,
    required this.originalBytes,
    required this.finalBytes,
    required this.wasCompressed,
  });
}

void _debugLog(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[MediaCaptureField] $message');
  }
}

/// A single reusable widget that implements the full capture flow required
/// across the app for photos/documents:
///
///   Take Photo (camera)  OR  Upload (gallery/file picker)
///        -> Crop / Rotate (photos only, not PDFs)
///        -> Auto-compress to the target size band for [kind]
///        -> Preview with Retake / Remove / Confirm(automatic)
///
/// This widget owns its own picked-file state and reports the final,
/// already-optimized file path back to the parent via [onChanged] once the
/// full pipeline (pick -> crop -> compress) has completed. Parents should
/// NOT re-compress or re-crop the path they receive.
///
/// [allowPdf] additionally allows selecting a PDF via the upload path (no
/// camera/crop applies to PDFs - only the max-size check does).
class MediaCaptureField extends StatefulWidget {
  final String label;
  final String? helperText;
  final MediaCaptureKind kind;
  final String? initialPath;
  final ValueChanged<String?> onChanged;
  final bool allowPdf;
  final bool required;

  const MediaCaptureField({
    super.key,
    required this.label,
    required this.kind,
    required this.onChanged,
    this.helperText,
    this.initialPath,
    this.allowPdf = false,
    this.required = false,
  });

  @override
  State<MediaCaptureField> createState() => _MediaCaptureFieldState();
}

class _MediaCaptureFieldState extends State<MediaCaptureField> {
  final ImagePicker _picker = ImagePicker();
  final MediaOptimizerService _optimizer = MediaOptimizerService();

  String? _path;
  bool _isPdf = false;
  bool _busy;
  String _busyLabel = '';
  int? _finalBytes;

  _MediaCaptureFieldState() : _busy = false;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _isPdf = _path != null && _optimizer.isPdf(_path!);
  }

  @override
  void didUpdateWidget(MediaCaptureField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPath != oldWidget.initialPath &&
        widget.initialPath != _path) {
      setState(() {
        _path = widget.initialPath;
        _isPdf = _path != null && _optimizer.isPdf(_path!);
      });
    }
  }

  Future<void> _setBusy(bool value, [String label = '']) async {
    if (!mounted) return;
    setState(() {
      _busy = value;
      _busyLabel = label;
    });
  }

  void _emit(String? path, {int? finalBytes}) {
    _path = path;
    _finalBytes = finalBytes;
    widget.onChanged(path);
    if (mounted) setState(() {});
  }

  Future<void> _showSourceSheet() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CaptureSourceSheet(allowPdf: widget.allowPdf),
    );
    if (source == null) return;
    switch (source) {
      case 'camera':
        await _captureFromCamera();
        break;
      case 'gallery':
        await _pickFromGallery();
        break;
      case 'pdf':
        await _pickPdf();
        break;
    }
  }

  Future<void> _captureFromCamera() async {
    try {
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (shot == null) return;
      await _handlePickedImage(shot.path, fromCamera: true);
    } catch (e) {
      _debugLog('Camera capture failed: $e');
      _showError('Unable to open the camera. Please try again.');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null) return;
      await _handlePickedImage(file.path, fromCamera: false);
    } catch (e) {
      _debugLog('Gallery pick failed: $e');
      _showError('Unable to open the gallery. Please try again.');
    }
  }

  Future<void> _pickPdf() async {
    // Lazily import file_picker usage only when PDFs are allowed, to avoid
    // pulling an extra dependency path for widgets that never need it.
    try {
      final result = await _pickPdfFile();
      if (result == null) return;
      final file = File(result);
      final exceeds = await _optimizer.pdfExceedsMaxSize(result);
      if (exceeds) {
        final sizeStr =
            MediaOptimizerService.formatBytes(await file.length());
        _showError(
          'This PDF is $sizeStr, which is larger than the 2MB limit. '
          'Please choose a smaller file or a scanned image instead.',
        );
        return;
      }
      _emit(result, finalBytes: await file.length());
    } catch (e) {
      _debugLog('PDF pick failed: $e');
      _showError('Unable to select the PDF. Please try again.');
    }
  }

  Future<String?> _pickPdfFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    return path;
  }

  Future<void> _handlePickedImage(String sourcePath,
      {required bool fromCamera}) async {
    // Only offer crop/rotate for camera-captured photos, or gallery/upload
    // photos too - either way a crop step helps the enumerator frame the
    // subject correctly before we lock in the compressed output.
    final aspectRatio = widget.kind == MediaCaptureKind.profilePhoto
        ? const CropAspectRatio(ratioX: 3, ratioY: 4) // portrait 600x800
        : null; // documents: free-form crop, keep original framing option
    await _setBusy(true, 'Preparing image...');
    try {
      final cropped = await _cropImage(sourcePath, aspectRatio);
      final workingPath = cropped ?? sourcePath;
      if (cropped == null && !fromCamera) {
        // User might have backed out of crop on a gallery pick - still
        // proceed with the original selection rather than losing the pick.
      }
      await _compressAndEmit(workingPath);
    } finally {
      await _setBusy(false);
    }
  }

  Future<String?> _cropImage(
      String sourcePath, CropAspectRatio? aspectRatio) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        aspectRatio: aspectRatio,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95, // final compression handled by MediaOptimizer
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: widget.kind == MediaCaptureKind.profilePhoto
                ? 'Crop Farmer Photo'
                : 'Crop / Rotate Document',
            toolbarColor: AppTheme.primaryGreen,
            toolbarWidgetColor: AppTheme.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: aspectRatio != null,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: widget.kind == MediaCaptureKind.profilePhoto
                ? 'Crop Farmer Photo'
                : 'Crop / Rotate Document',
            aspectRatioLockEnabled: aspectRatio != null,
          ),
          WebUiSettings(context: context),
        ],
      );
      return cropped?.path;
    } catch (e) {
      _debugLog('Crop step skipped/failed: $e');
      // If cropping isn't available on this platform/build, fall back to
      // using the picked image as-is rather than blocking the enumerator.
      return null;
    }
  }

  Future<void> _compressAndEmit(String path) async {
    await _setBusy(true, 'Optimizing...');
    try {
      final OptimizedMedia optimized;
      if (widget.kind == MediaCaptureKind.profilePhoto) {
        optimized = await _optimizer.optimizeProfilePhoto(path);
      } else {
        optimized = await _optimizer.optimizeDocumentPhoto(path);
      }
      _isPdf = false;
      _emit(optimized.path, finalBytes: optimized.finalBytes);
    } catch (e) {
      _debugLog('Compression failed, using original: $e');
      final bytes = await File(path).length();
      _emit(path, finalBytes: bytes);
    } finally {
      await _setBusy(false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  void _remove() {
    _emit(null, finalBytes: null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (widget.required)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('*',
                    style: TextStyle(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 2),
          Text(widget.helperText!,
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
        const SizedBox(height: 8),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (_busy) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: AppTheme.paleGreen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppTheme.primaryGreen),
            ),
            const SizedBox(height: 10),
            Text(_busyLabel,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_path == null || _path!.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              onTap: _captureFromCamera,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.upload_file_outlined,
              label: 'Upload',
              onTap: widget.allowPdf ? _showSourceSheet : _pickFromGallery,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _isPdf
                ? Container(
                    width: 56,
                    height: 56,
                    color: AppTheme.paleGreen,
                    child: const Icon(Icons.picture_as_pdf,
                        color: AppTheme.primaryGreen, size: 28),
                  )
                : (kIsWeb
                    ? Image.network(_path!,
                        width: 56, height: 56, fit: BoxFit.cover)
                    : Image.file(File(_path!),
                        width: 56, height: 56, fit: BoxFit.cover)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.check_circle,
                        size: 16, color: AppTheme.success),
                    SizedBox(width: 6),
                    Text('Ready',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success)),
                  ],
                ),
                if (_finalBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      MediaOptimizerService.formatBytes(_finalBytes!),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (!_isPdf)
            IconButton(
              tooltip: 'Retake',
              icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
              onPressed: _showSourceSheet,
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, color: AppTheme.danger),
            onPressed: _remove,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.paleGreen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightGreen.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primaryGreen, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryGreen)),
          ],
        ),
      ),
    );
  }
}

class _CaptureSourceSheet extends StatelessWidget {
  final bool allowPdf;
  const _CaptureSourceSheet({required this.allowPdf});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppTheme.primaryGreen),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: AppTheme.primaryGreen),
              title: const Text('Choose Image'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (allowPdf)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined,
                    color: AppTheme.primaryGreen),
                title: const Text('Choose PDF'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
          ],
        ),
      ),
    );
  }
}


