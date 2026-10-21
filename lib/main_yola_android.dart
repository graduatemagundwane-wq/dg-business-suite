// Yola Android — share the existing live Yola UI rather than redrawing it.
// The native shell is intentionally NOT an offline POS: the hosted API must
// be reachable for authentication, transactions and reports.
// Offline checkout needs the desktop SQLite/API backend ported to Android
// before this may be called a production replacement.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const yolaWebUrl = String.fromEnvironment(
  'YOLA_BASE_URL',
  defaultValue: 'https://yola-onboarding.vercel.app/',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Never lock rotation: landscape tablets must receive the same responsive
  // desktop sidebar and workspace as the existing Yola web/Windows frontend.
  runApp(const YolaAndroidApp());
}

class YolaAndroidApp extends StatelessWidget {
  const YolaAndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Yola — Powered by Double Gee Tech',
      debugShowCheckedModeBanner: false,
      home: YolaWorkspaceWebView(),
    );
  }
}

class YolaWorkspaceWebView extends StatefulWidget {
  const YolaWorkspaceWebView({super.key});

  @override
  State<YolaWorkspaceWebView> createState() => _YolaWorkspaceWebViewState();
}

class _YolaWorkspaceWebViewState extends State<YolaWorkspaceWebView> {
  late final WebViewController _web;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _loading = true; _failed = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Broken icons/fonts should not hide an otherwise usable POS.
            if (error.isForMainFrame != false && mounted) {
              setState(() { _loading = false; _failed = true; });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            // Never load insecure HTTP or untrusted local file URLs.
            if (uri.scheme == 'https' || uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(yolaWebUrl));
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  Future<void> _retry() async {
    setState(() { _failed = false; _loading = true; });
    await _web.loadRequest(Uri.parse(yolaWebUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _web),
              if (_loading && !_failed)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(minHeight: 2.5),
                ),
              if (_failed)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xFFF8FAFC),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded,
                                  color: Color(0xFF12273B), size: 48),
                              const SizedBox(height: 20),
                              const Text('Cannot open Yola',
                                  style: TextStyle(
                                      fontSize: 23, fontWeight: FontWeight.w800,
                                      color: Color(0xFF12273B))),
                              const SizedBox(height: 10),
                              const Text(
                                'This Android test candidate requires a connection '
                                'to the existing Yola server. Offline sales are '
                                'not enabled in this build.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF52687B)),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: _retry,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF12273B),
                                  minimumSize: const Size(180, 48),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
