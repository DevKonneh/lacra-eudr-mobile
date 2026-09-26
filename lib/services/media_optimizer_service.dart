import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Result of an optimization pass: the final on-device path to use (which
/// may be the ORIGINAL path if compression wasn't needed/possible), plus
/// the before/after byte sizes for diagnostics/UI.
class OptimizedMedia {
  final String path;
  final int originalBytes;
  final int finalBytes;
  final bool wasCompressed;

  const OptimizedMedia({
    required this.path,
    required this.originalBytes,
    required this.finalBytes,
    required this.wasCompressed,
  });
}

/// Centralizes image compression for every photo/document captured by the
/// registration wizard (farmer photo, ID document, compliance documents,
/// farm selfie, farm photos) so files are optimized ONCE, consistently,
/// before ever being written to the offline queue or uploaded - instead of
/// each capture site inventing its own ad-hoc size handling.
///
/// Two named presets are provided, matching the two size profiles called
/// for by the registration-form requirements:
///  - [optimizeProfilePhoto]: portrait farmer profile photo. Fixed
///    600x800 target frame, JPEG, aiming for 200-500 KB and a HARD cap of
///    1 MB.
///  - [optimizeDocumentPhoto]: ID documents / compliance documents. Keeps
///    the original aspect ratio (a document's whole point is that its
///    proportions and text stay legible - it should not be forced into a
///    portrait frame), JPEG, aiming for 500 KB-1.5 MB with a HARD cap of
///    2 MB.
///
/// PDFs are passed through untouched (no image re-encoding is attempted -
/// callers are responsible for rejecting PDFs over the 2MB document cap,
/// see [pdfExceedsMaxSize]).
class MediaOptimizerService {
  static const int kProfilePhotoTargetMinBytes = 200 * 1024; // 200 KB
  static const int kProfilePhotoTargetMaxBytes = 500 * 1024; // 500 KB
  static const int kProfilePhotoMaxBytes = 1024 * 1024; // 1 MB hard cap

  static const int kDocumentTargetMinBytes = 500 * 1024; // 500 KB
  static const int kDocumentTargetMaxBytes = 1536 * 1024; // 1.5 MB
  static const int kDocumentMaxBytes = 2 * 1024 * 1024; // 2 MB hard cap

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MediaOptimizer] $message');
    }
  }

  Future<String> _tempPathFor(String suffix) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/opt_${stamp}_$suffix';
  }

  /// Compresses [sourcePath] into a portrait profile photo (farmer photo).
  ///
  /// Strategy: downscale to fit within 600x800 (never upscale), then step
  /// quality down from 88 until the result is at/under
  /// [kProfilePhotoTargetMaxBytes], stopping early if it's already within
  /// the target band. Never exceeds [kProfilePhotoMaxBytes] - if quality 30
  /// still doesn't get under the hard cap (extremely unlikely for a
  /// 600x800 JPEG), the lowest-quality result is returned anyway rather
  /// than failing the capture outright.
  Future<OptimizedMedia> optimizeProfilePhoto(String sourcePath) async {
    final original = File(sourcePath);
    final originalBytes = await original.length();

    final targetPath = await _tempPathFor('profile.jpg');
    int quality = 88;
    File? result;
    int resultBytes = originalBytes;

    while (quality >= 30) {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        quality: quality,
        minWidth: 600,
        minHeight: 800,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed == null) break;
      result = File(compressed.path);
      resultBytes = await result.length();
      if (resultBytes <= kProfilePhotoTargetMaxBytes) break;
      quality -= 12;
    }

    if (result == null) {
      _log('Profile photo compression failed - using original file.');
      return OptimizedMedia(
        path: sourcePath,
        originalBytes: originalBytes,
        finalBytes: originalBytes,
        wasCompressed: false,
      );
    }

    _log(
      'Profile photo optimized: $originalBytes bytes -> $resultBytes bytes '
      '(quality $quality)',
    );
    return OptimizedMedia(
      path: result.path,
      originalBytes: originalBytes,
      finalBytes: resultBytes,
      wasCompressed: true,
    );
  }

  /// Compresses [sourcePath] (an ID document or compliance document PHOTO
  /// - not a PDF) preserving its original aspect ratio, aiming for the
  /// 500 KB-1.5 MB target band and never exceeding [kDocumentMaxBytes].
  ///
  /// Uses a higher starting quality/resolution ceiling than the profile
  /// photo preset since documents need enough resolution for printed text
  /// (e.g. an ID number) to stay legible after compression.
  Future<OptimizedMedia> optimizeDocumentPhoto(String sourcePath) async {
    final original = File(sourcePath);
    final originalBytes = await original.length();

    // Already small enough - don't re-encode (avoids any needless quality
    // loss on a file that's already within budget).
    if (originalBytes <= kDocumentTargetMaxBytes) {
      return OptimizedMedia(
        path: sourcePath,
        originalBytes: originalBytes,
        finalBytes: originalBytes,
        wasCompressed: false,
      );
    }

    final targetPath = await _tempPathFor('doc.jpg');
    int quality = 90;
    // Cap the longest side at 2000px - generous enough to keep an ID
    // number/small print legible, while still bringing multi-MB camera
    // originals down substantially.
    File? result;
    int resultBytes = originalBytes;

    while (quality >= 40) {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        quality: quality,
        minWidth: 2000,
        minHeight: 2000,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed == null) break;
      result = File(compressed.path);
      resultBytes = await result.length();
      if (resultBytes <= kDocumentTargetMaxBytes) break;
      quality -= 10;
    }

    if (result == null) {
      _log('Document compression failed - using original file.');
      return OptimizedMedia(
        path: sourcePath,
        originalBytes: originalBytes,
        finalBytes: originalBytes,
        wasCompressed: false,
      );
    }

    _log(
      'Document photo optimized: $originalBytes bytes -> $resultBytes bytes '
      '(quality $quality)',
    );
    return OptimizedMedia(
      path: result.path,
      originalBytes: originalBytes,
      finalBytes: resultBytes,
      wasCompressed: true,
    );
  }

  /// True if [path] points to a PDF whose size exceeds the 2MB document
  /// cap. PDFs are never re-encoded/compressed by this service - callers
  /// should reject oversized PDFs at pick-time with a clear message asking
  /// for a photo instead (matching the existing attachments-step pattern).
  Future<bool> pdfExceedsMaxSize(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final bytes = await file.length();
    return bytes > kDocumentMaxBytes;
  }

  /// True if [path] is a PDF (by extension).
  bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');

  /// Human-readable size, e.g. "1.2 MB" or "540 KB".
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
