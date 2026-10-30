import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  String? _url;
  String _title = 'Details';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      // Arguments are either a plain String (the URL - used by the QR
      // scanner, kept for backward compatibility) or a Map with 'url' and
      // optional 'title' keys (used by the License & Permit Application
      // entry point, which needs a custom app-bar title).
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _url = args;
      } else if (args is Map) {
        _url = args['url'] as String?;
        _title = (args['title'] as String?) ?? _title;
      }
      _initializeWebView();
    }
  }

  void _initializeWebView() {
    if (_url == null || _url!.isEmpty) {
      setState(() {
        _errorMessage = 'No URL provided';
        _isLoading = false;
      });
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.description;
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_url!));

    // CRITICAL: Android's WebView does NOT support HTML
    // `<input type="file">` uploads out of the box - tapping an upload
    // control inside a page like the LACRA /apply registration form
    // silently does nothing unless the host app supplies a file-selector
    // handler. iOS's WKWebView-based implementation already has native
    // file-chooser support, so this is only needed on Android.
    final platformController = _controller!.platform;
    if (!kIsWeb && Platform.isAndroid && platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  // Bridges Android WebView's native file-chooser request to Flutter's
  // file_picker package. Returns the selected file(s) as `file://` URIs,
  // which is what the platform's underlying ValueCallback<Uri[]> expects.
  // An empty list (e.g. the user cancels, or picking fails) correctly
  // cancels the web page's upload dialog rather than leaving it hanging.
  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      final paths = result?.files
          .map((f) => f.path)
          .whereType<String>()
          .toList();
      if (paths == null || paths.isEmpty) return [];
      return paths.map((p) => Uri.file(p).toString()).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WebView file selector error: $e');
      }
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller?.reload();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error loading page',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF757575),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        _controller?.reload();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_controller != null)
            WebViewWidget(controller: _controller!),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
        ],
      ),
    );
  }
}
