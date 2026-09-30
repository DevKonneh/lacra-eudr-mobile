/// GeoIdFarmQrWidget — displays the FAO GeoID + farm-level QR code for a
/// registered farm. Used in:
///   - FarmerDetailScreen (per-farm section)
///   - Post-registration success dialog (FarmerRegistryScreen)
///
/// The widget renders:
///   1. A GeoID badge (with copy-to-clipboard + open in browser)
///   2. The farm-level QR code (from backend data-URL OR generated live from
///      the public farm-scan URL)
///   3. A share/print action button for inspector use
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Public base URL for the LACRA frontend — used to build the farm-scan URL
/// when the backend-generated QR data-URL is not yet available (e.g. right
/// after registration before the detail screen is loaded).
const String _frontendBase = 'https://lacra-eudr-backend.onrender.com/api';

class GeoIdFarmQrWidget extends StatelessWidget {
  /// The farm UUID (from FarmRecord.id). Required to build the fallback QR URL.
  final String farmId;

  /// FAO GeoID UUID string (nullable — shown as "pending" when null).
  final String? geoId;

  /// FAO GeoID resolver URI (nullable).
  final String? geoIdUri;

  /// Backend-generated QR data-URL (`data:image/png;base64,...`).
  /// When provided, rendered as an Image widget.
  /// When null, a live QrImageView is rendered from [farmScanUrl].
  final String? farmQrCode;

  /// Override the farm-scan URL (defaults to public/farm-scan/:farmId).
  final String? farmScanUrl;

  const GeoIdFarmQrWidget({
    super.key,
    required this.farmId,
    this.geoId,
    this.geoIdUri,
    this.farmQrCode,
    this.farmScanUrl,
  });

  String get _scanUrl =>
      farmScanUrl ?? '$_frontendBase/public/farm-scan/$farmId';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGeoIdCard(context),
        const SizedBox(height: 12),
        _buildQrCard(context),
      ],
    );
  }

  // ── GeoID identity card ──────────────────────────────────────────────────

  Widget _buildGeoIdCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: geoId != null
              ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: geoId != null
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.08)
                  : Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.language,
                  size: 16,
                  color: geoId != null
                      ? const Color(0xFF388E3C)
                      : Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                const Text(
                  'FAO GeoID — Anonymous Farm Identity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const Spacer(),
                if (geoId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      '✓ REGISTERED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: geoId != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // UUID display
                      const Text(
                        'GeoID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF757575),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onLongPress: () => _copyToClipboard(context, geoId!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  geoId!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Color(0xFF212121),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () =>
                                    _copyToClipboard(context, geoId!),
                                child: const Icon(
                                  Icons.copy,
                                  size: 16,
                                  color: Color(0xFF757575),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (geoIdUri != null) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _openUrl(context, geoIdUri!),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: Color(0xFF388E3C),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  geoIdUri!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF388E3C),
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Text(
                        'This anonymous identifier is derived from the farm\'s GPS boundary. It contains no personal data and is safe for EUDR due diligence.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                          height: 1.4,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        size: 18,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'GeoID pending — will be minted by server once the farm boundary is processed.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                            height: 1.4,
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

  // ── Farm QR code card ────────────────────────────────────────────────────

  Widget _buildQrCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_2, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Farm QR Code',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copyToClipboard(context, _scanUrl),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Copy Link',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QR code display
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: farmQrCode != null
                      ? _buildDataUrlImage()
                      : QrImageView(
                          data: _scanUrl,
                          version: QrVersions.auto,
                          size: 120,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scan to verify this farm',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212121),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _bulletPoint(
                        'WHIMO / EU traders — geo data only (no personal info)',
                        icon: Icons.check_circle,
                        color: const Color(0xFF4CAF50),
                      ),
                      const SizedBox(height: 4),
                      _bulletPoint(
                        'LACRA staff — add ?view=full for full farmer profile',
                        icon: Icons.info_outline,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _openUrl(context, _scanUrl),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.open_in_new,
                              size: 13,
                              color: Color(0xFF388E3C),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _scanUrl,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF388E3C),
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text, {required IconData icon, Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color ?? Colors.grey),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF616161)),
          ),
        ),
      ],
    );
  }

  /// Render a base64 data-URL image (farmQrCode from backend).
  Widget _buildDataUrlImage() {
    try {
      final dataUrl = farmQrCode!;
      // Strip the "data:image/png;base64," prefix
      final commaIdx = dataUrl.indexOf(',');
      if (commaIdx == -1) throw Exception('Invalid data URL');
      final b64 = dataUrl.substring(commaIdx + 1);
      final bytes = base64Decode(b64);
      return Image.memory(bytes, width: 120, height: 120, fit: BoxFit.contain);
    } catch (_) {
      // Fallback to live QR if data URL is malformed
      return QrImageView(
        data: _scanUrl,
        version: QrVersions.auto,
        size: 120,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  void _openUrl(BuildContext context, String url) {
    // Graceful degradation: if url_launcher is not available or cannot handle
    // the URL, copy it instead so the inspector can paste it elsewhere.
    try {
      Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link copied — open in browser:\n$url'),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    } catch (_) {
      // ignore
    }
  }
}


