// Yola Worker for SARGO. Uses the SAME hosted Yola account database, cookies,
// stock and checkout API as the owner app. No separate worker credentials.
// Native WebView role gate is additional to SERVER-SIDE worker permissions.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _host = 'https://yola-onboarding.vercel.app/';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YolaWorkerApplication());
}

class YolaWorkerApplication extends StatelessWidget {
  const YolaWorkerApplication({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'Yola Worker · Double Gee Tech',
        debugShowCheckedModeBanner: false,
        home: YolaWorkerWorkspace(),
      );
}

class YolaWorkerWorkspace extends StatefulWidget {
  const YolaWorkerWorkspace({super.key});
  @override
  State<YolaWorkerWorkspace> createState() => _YolaWorkerWorkspaceState();
}

class _YolaWorkerWorkspaceState extends State<YolaWorkerWorkspace> {
  late final WebViewController _web;
  bool _loading = true;
  bool _blocked = false;
  bool _failed = false;
  int _navigationVersion = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'about') return NavigationDecision.navigate;
          return uri.scheme == 'https' && uri.origin == Uri.parse(_host).origin
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          _navigationVersion += 1;
          if (mounted) {
            setState(() {
              _loading = true;
              _blocked = false;
              _failed = false;
            });
          }
        },
        onPageFinished: _guardPage,
        onWebResourceError: (error) {
          if (error.isForMainFrame != false && mounted) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(_host));
  }

  Future<void> _guardPage(String url) async {
    final serial = _navigationVersion;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.origin != Uri.parse(_host).origin) {
      if (mounted) setState(() => _blocked = true);
      return;
    }
    try {
      if (uri.path == '/workspace.html') {
        final workerAllowed = await _web.runJavaScriptReturningResult('''
          (async () => {
            try {
              const r = await fetch('/api/me', {
                cache: 'no-store', credentials: 'same-origin'
              });
              if (!r.ok) return false;
              const result = await r.json();
              return result.authenticated === true &&
                     result.user?.role === 'worker' &&
                     result.user?.businessCode === 'YOLA-D8C868892683ECCE' &&
                     result.user?.license?.active === true;
            } catch (e) { return false; }
          })();
        ''');
        if (serial != _navigationVersion) return;
        if (workerAllowed != true &&
            workerAllowed.toString().toLowerCase() != 'true') {
          if (mounted) setState(() {
            _blocked = true;
            _loading = false;
          });
          return;
        }
        await _web.runJavaScript('''
          // Keep the original Yola fonts, logo, sidebar, colours and layout.
          // Worker is only allowed to navigate to Sell in this app.
          if (typeof roleAllow === 'function') {
            roleAllow = function(page) { return page === 'sell'; };
          }
          if (typeof go === 'function') {
            go('sell');
          }
          const nav = document.getElementById('sidebar-nav');
          if (nav) {
            [...nav.querySelectorAll('[data-page]')].forEach(
              el => { if (el.dataset.page !== 'sell') el.remove(); });
          }
        ''');
      } else if (uri.path == '/' || uri.path.isEmpty) {
        // Worker sign-in is the original Yola sign-in, not a copied password.
        await _web.runJavaScript('''
          try {
            if (typeof formMode !== 'undefined' &&
                typeof authPage === 'function' &&
                document.getElementById('authform')) {
              formMode = 'login';
              authPage();
            }
          } catch (e) {}
        ''');
      } else {
        if (mounted) setState(() {
          _blocked = true;
          _loading = false;
        });
        return;
      }
      if (serial == _navigationVersion && mounted) {
        setState(() {
          _loading = false;
          _blocked = false;
        });
      }
    } catch (_) {
      if (serial == _navigationVersion && mounted) {
        setState(() {
          _loading = false;
          _blocked = true;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _web.runJavaScript('''
        (async () => {
          try {
            await fetch('/api/logout', {
              method:'POST', credentials:'same-origin',
              headers:{'Content-Type':'application/json'},
              body:'{}'
            });
          } catch (e) {}
          location.replace('/');
        })();
      ''');
    } catch (_) {
      await _web.loadRequest(Uri.parse(_host));
    }
  }

  Future<void> _back() async {
    if (_blocked) {
      await _signOut();
      return;
    }
    // Don't exit the worker app on Android back; maintain checkout session.
    final uri = Uri.tryParse(await _web.currentUrl() ?? '');
    if (uri?.path == '/workspace.html') {
      await _web.runJavaScript(
        "if (typeof go==='function') go('sell');");
      return;
    }
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: Stack(children: [
              if (!_blocked && !_failed)
                WebViewWidget(controller: _web),
              if (_loading)
                const LinearProgressIndicator(minHeight: 2.5),
              if (_blocked)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            color: Color(0xFF152E48), size: 50),
                        const SizedBox(height: 16),
                        const Text('Worker accounts only',
                            style: TextStyle(
                                fontSize: 23, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        const Text(
                          'This Yola app only accepts an active Worker account. '
                          'Ask your administrator to create your worker login '
                          'in Team Accounts.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _signOut,
                          child: const Text('Sign out / Worker sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_failed)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off, size: 48),
                      const SizedBox(height: 12),
                      const Text('Connect to the internet to use Yola Worker.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _web.loadRequest(Uri.parse(_host)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      );
}