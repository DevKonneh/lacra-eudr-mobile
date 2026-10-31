import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

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
      // CRITICAL: Android's WebView has no working `<a download>` / blob
      // download handling and `window.print()` is a silent no-op (there
      // is no print renderer wired up by default) - this is exactly why
      // the LACRA /apply registration wizard's "Download Application
      // Summary" and "Print Application" buttons appeared to do nothing
      // when opened inside this embedded WebView, even though they work
      // fine in a normal mobile/desktop browser. To fix this without any
      // fragile blob/download interception, the web page itself detects
      // this JavaScript channel (`window.LacraDocument`) and, when
      // present, posts the generated PDF as a base64 JSON payload here
      // instead of calling the browser APIs - see `_handleDocumentMessage`
      // below, which hands the bytes off to Android's native print/share
      // UI via the `printing` package (print dialog supports "Save as
      // PDF" too, so one native entry point covers both actions).
      ..addJavaScriptChannel(
        'LacraDocument',
        onMessageReceived: _handleDocumentMessage,
      )
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
    if (!kIsWeb &&
        Platform.isAndroid &&
        platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  // Handles a message posted by the web page's `window.LacraDocument`
  // bridge. Expected JSON payload: {"action": "print"|"download",
  // "filename": "...", "base64": "<pdf bytes, no data: prefix>"}.
  // "print" opens Android's native print dialog (which also offers "Save
  // as PDF"); "download" goes straight to the share sheet so the user can
  // save it to Files, email it, etc. Both actions ultimately rely on the
  // same decoded PDF bytes, so a failure to parse/decode the payload is
  // reported back to the user rather than failing silently.
  Future<void> _handleDocumentMessage(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String? ?? 'download';
      final filename = (data['filename'] as String?) ?? 'document.pdf';
      final base64Data = data['base64'] as String?;
      if (base64Data == null || base64Data.isEmpty) {
        throw Exception('No document data received');
      }
      final bytes = base64Decode(base64Data);

      if (action == 'print') {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WebView document bridge error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the document. Please try again.'),
          ),
        );
      }
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
