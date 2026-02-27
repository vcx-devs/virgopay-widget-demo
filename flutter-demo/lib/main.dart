import 'dart:convert'; // JSON encode/decode for message passing
import 'dart:io'; // Platform check (Android)

import 'package:file_picker/file_picker.dart'; // Android file chooser for <input type="file">
import 'package:flutter/material.dart'; // Flutter UI
import 'package:url_launcher/url_launcher.dart'; // Open external browser / mail
import 'package:webview_flutter/webview_flutter.dart'; // WebView core
import 'package:webview_flutter_android/webview_flutter_android.dart'; // Android WebView extras

void main() {
  // Minimal app shell: no routing, no extra global config.
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WidgetWebViewPage(),
  ));
}

class WidgetWebViewPage extends StatefulWidget {
  const WidgetWebViewPage({super.key});

  @override
  State<WidgetWebViewPage> createState() => _WidgetWebViewPageState();
}

class _WidgetWebViewPageState extends State<WidgetWebViewPage> {
  late final WebViewController _controller;

  bool _bridgeInjected = false; // Inject JS bridge only once
  bool _configSent = false; // Avoid sending config repeatedly

  // Local (page-scoped) nonce storage. No global class needed.
  String _nonce = '';

  // ===== Hardcoded widget URL & config =====
  // Android emulator must use 10.0.2.2 to reach your computer's localhost.
  static const String widgetUrl =
      'https://sandbox.virgopay.co/page#/widget/login?type=2&code=Kuroky';

  static const String theme = 'dark';
  static const String primaryColor = '#ffcc00';
  static const String addressInfo = 'ENCRYPTED_ADDRESS_STRING';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      // Allow JavaScript (required for modern widgets)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)

      // JS -> Flutter channel (widget sends messages via window.NativeBridge.postMessage)
      ..addJavaScriptChannel(
        'NativeBridge',
        onMessageReceived: (JavaScriptMessage message) async {
          await _handleMessageFromJs(message.message);
        },
      )

      // WebView lifecycle & navigation interception
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            // Inject a stable bridge after the page loads
            if (!_bridgeInjected) {
              _bridgeInjected = true;
              await _injectBridge();
            }
          },
          onNavigationRequest: (request) async {
            // Intercept non-http(s) URLs and open them externally
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
            if (!isHttp) {
              await _openExternal(uri.toString());
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Android: enable file selection for <input type="file">
    if (Platform.isAndroid) {
      final androidController = _controller.platform as AndroidWebViewController;

      androidController.setOnShowFileSelector((params) async {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          withData: false,
        );

        // User cancelled
        if (result == null) return <String>[];

        // Return selected files as file:// URIs
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      });

      AndroidWebViewController.enableDebugging(true);
    }

    // Load widget page
    _controller.loadRequest(Uri.parse(widgetUrl));
  }

  /// Injects a stable JS API:
  /// - Widget can call: window.WidgetHost.postMessage(objOrString)
  /// - Bridge forwards to: window.NativeBridge.postMessage(string) -> Flutter
  Future<void> _injectBridge() async {
    const js = r"""
      (function() {
        try {
          if (!window.WidgetHost) window.WidgetHost = {};
          if (!window.WidgetHost.postMessage) {
            window.WidgetHost.postMessage = function(data) {
              try {
                if (typeof data !== 'string') data = JSON.stringify(data);
              } catch (e) {}

              try {
                if (window.NativeBridge && window.NativeBridge.postMessage) {
                  window.NativeBridge.postMessage(String(data));
                }
              } catch (e) {}
            };
          }
        } catch (e) {}
      })();
    """;

    await _controller.runJavaScript(js);
  }

  /// Parses and handles messages coming from the widget (via NativeBridge).
  Future<void> _handleMessageFromJs(String raw) async {
    Map<String, dynamic> msg;

    // Widget should send JSON string. If invalid, ignore.
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = (msg['type'] ?? '').toString();
    final payload = (msg['payload'] is Map)
        ? (msg['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    // Handshake: widget requests config
    if (type == 'REQUEST_CONFIG') {
      await _sendWidgetConfig();
      return;
    }

    switch (type) {
      case 'OPEN_LINK':
        // payload.url: open in device default browser
        await _openExternal((payload['url'] ?? '').toString());
        break;

      case 'MAIL_TO':
        // payload.url: mailto:... open with mail app
        await _openExternal((payload['url'] ?? '').toString());
        break;

      case 'NONCE':
        // payload.nonce: store for session restore
        final n = (payload['nonce'] ?? '').toString();
        if (n.isNotEmpty) _nonce = n;
        break;

      case 'LOG_OUT':
        // Widget logout: clear stored nonce and allow config re-send
        _nonce = '';
        _configSent = false;
        break;

      default:
        // Ignore unknown messages
        break;
    }
  }

  /// Sends WIDGET_CONFIG to the widget by calling a widget-side JS entrypoint:
  /// window.__WIDGET_ON_MESSAGE__(<json-string>)
  Future<void> _sendWidgetConfig() async {
    if (_configSent) return;
    _configSent = true;

    final msgObj = <String, dynamic>{
      'type': 'WIDGET_CONFIG',
      'payload': <String, dynamic>{
        'hostApp': 'flutter',
        'isEmbedded': true,
        'isMobileApp': true, // IMPORTANT: tell widget this is mobile app environment
        'host': 'flutterApp',
        'theme': theme,
        'primaryColor': primaryColor,
        'addressInfo': addressInfo,
        'nonce': _nonce,
        // Optional fields you may enable later:
        // 'bgColor': null,
        // 'fontColor': null,
        // 'logoUrl': null,
      }
    };

    final jsonStr = jsonEncode(msgObj);

    // Pass the JSON string as a JS string parameter safely via jsonEncode(...)
    final jsCall = "window.__WIDGET_ON_MESSAGE__(${jsonEncode(jsonStr)});";
    await _controller.runJavaScript(jsCall);
  }

  /// Opens a URL using the system external application (browser/mail).
  Future<void> _openExternal(String url) async {
    if (url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Prevent layout resize when keyboard appears (reduces "jumping" in WebView)
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('VirgoPay Widget'),
      ),
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}