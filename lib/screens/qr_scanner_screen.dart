import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../routes/app_routes.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  String? _scannedUrl;
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _handleQRCode(BarcodeCapture barcodeCapture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Get scan type
    final String? type = ModalRoute.of(context)?.settings.arguments as String?;
    final String scanType = type == 'farmer' ? 'Farmer' : 'Batch';

    // Log QR scan results (debug only)
    _log('========================================');
    _log('QR CODE SCANNED - $scanType Details');
    _log('========================================');
    _log('Raw QR Code Value: $code');
    _log('Scan Type: $scanType');
    _log('QR Code Length: ${code.length}');

    // Check if it's a valid URL
    final bool isValidUrl = _isValidUrl(code);
    _log('Is Valid URL: $isValidUrl');

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Validate if it's a URL
    if (isValidUrl) {
      _log('URL Scheme: ${Uri.parse(code).scheme}');
      _log('URL Host: ${Uri.parse(code).host}');
      _log('URL Path: ${Uri.parse(code).path}');
      _log('Full URL: $code');
      _log('✅ Valid URL - Navigating to WebView');
      _log('========================================');

      setState(() {
        _scannedUrl = code;
      });

      // Stop camera
      cameraController.stop();

      // Navigate to webview
      Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.webview, arguments: code);
    } else {
      _log('❌ Invalid QR Code - Not a valid URL');
      _log('Error: QR code does not contain a valid HTTP/HTTPS URL');
      _log('========================================');

      setState(() {
        _errorMessage = 'Invalid QR code. Please scan a valid URL.';
        _isProcessing = false;
      });
    }
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  void _handleBack() {
    cameraController.stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final String? type = ModalRoute.of(context)?.settings.arguments as String?;
    final String title = type == 'farmer'
        ? 'Farmer QR Scanner'
        : 'Batch QR Scanner';
    final String info = type == 'farmer'
        ? 'Position the QR code within the frame to scan farmer details'
        : 'Position the QR code within the frame to scan batch details';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          // Camera View
          MobileScanner(controller: cameraController, onDetect: _handleQRCode),

          // Overlay with instructions
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black.withOpacity(0.7),
              child: Column(
                children: [
                  Text(
                    info,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Scanning frame overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF4CAF50), width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  // Corner indicators
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFF4CAF50), width: 4),
                          left: BorderSide(color: Color(0xFF4CAF50), width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFF4CAF50), width: 4),
                          right: BorderSide(color: Color(0xFF4CAF50), width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFF4CAF50),
                            width: 4,
                          ),
                          left: BorderSide(color: Color(0xFF4CAF50), width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFF4CAF50),
                            width: 4,
                          ),
                          right: BorderSide(color: Color(0xFF4CAF50), width: 4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                    onPressed: () {
                      cameraController.toggleTorch();
                    },
                    tooltip: 'Toggle Flash',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      cameraController.switchCamera();
                    },
                    tooltip: 'Switch Camera',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _handleBack,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
