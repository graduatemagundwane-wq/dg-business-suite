// Yola Android: keep the exact hosted Yola UI for online operation.
// Android-native offline cashier is isolated, device-bound and licence gated.
// Never show offline transactions as synced until the cloud reconciles them.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'yola_android/offline_workspace.dart';
import 'yola_android/offline_store.dart';

const yolaWebUrl = String.fromEnvironment(
  'YOLA_BASE_URL',
  defaultValue: 'https://yola-onboarding.vercel.app/',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  bool _loading=true, _failed=false, _online=true;
  int _initialOfflineTab = 0;
  Completer<int>? _catalogRequest;
  String? _catalogNonce;

  String _nonce() => List.generate(24, (_) =>
    Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();

  Future<void> _receiveCatalog(JavaScriptMessage message) async {
    final request=_catalogRequest;
    if (request == null || request.isCompleted) return;
    try {
      final url=await _web.currentUrl();
      if (url == null || Uri.parse(url).origin != Uri.parse(yolaWebUrl).origin) {
        throw StateError('Offline inventory can only be imported from the official Yola website.');
      }
      final body=(jsonDecode(message.message) as Map).cast<String,dynamic>();
      if (body['nonce'] != _catalogNonce) throw StateError('Invalid catalog response.');
      if (body['error'] != null) throw StateError(body['error'].toString());
      final user=(body['user'] as Map).cast<String,dynamic>();
      final businessId=(user['business_id'] ??
        user['businessId'] ??
        (user['license'] is Map ? (user['license'] as Map)['business_id'] : null))?.toString();
      if (businessId == null || businessId.isEmpty) {
        throw StateError('Yola API did not provide an authenticated business identifier. Offline import blocked.');
      }
      final raw=body['products'];
      if (raw is! List) throw StateError('Yola inventory API returned invalid data.');
      await YolaOfflineStore.instance.importOnlineCatalog(
        onlineBusinessId:businessId,
        onlineRole:user['role']?.toString() ?? '',
        onlineProducts:raw);
      if (!request.isCompleted) request.complete(raw.length);
    } catch(e) {
      if (!request.isCompleted) request.completeError(e);
    }
  }

  Future<int> _cacheOnlineProducts() async {
    if (_failed) throw StateError('Connect to Yola and sign in before caching products.');
    if (_catalogRequest != null) throw StateError('Inventory transfer already running.');
    final url=await _web.currentUrl();
    if (url == null || Uri.parse(url).origin != Uri.parse(yolaWebUrl).origin) {
      throw StateError('Only the official Yola origin can prepare an offline catalog.');
    }
    final request=Completer<int>();
    final nonce=_nonce();
    _catalogRequest=request;
    _catalogNonce=nonce;
    try {
      await _web.runJavaScript("""
        (async function() {
          const nonce = '$nonce';
          try {
            const [meResponse, productsResponse] = await Promise.all([
              fetch('/api/me', {credentials:'same-origin',cache:'no-store'}),
              fetch('/api/pos/products', {credentials:'same-origin',cache:'no-store'})
            ]);
            if (!meResponse.ok || !productsResponse.ok) {
              throw Error('Please sign into online Yola before saving offline products.');
            }
            const me = await meResponse.json();
            const inventory = await productsResponse.json();
            if (!me.authenticated || !me.user || !me.user.license ||
                me.user.license.active !== true) {
              throw Error('Online account is not licensed and signed in.');
            }
            YolaNativeCatalog.postMessage(JSON.stringify({
              nonce, user:me.user, products:inventory.products
            }));
          } catch (e) {
            YolaNativeCatalog.postMessage(JSON.stringify({
              nonce, error:String(e)
            }));
          }
        })();
      """);
      return await request.future.timeout(const Duration(seconds:25));
    } finally {
      _catalogRequest=null;
      _catalogNonce=null;
    }
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..addJavaScriptChannel('YolaNativeCatalog',
          onMessageReceived:_receiveCatalog)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted:(_) {
          if (mounted) setState(() {_loading=true;_failed=false;});
        },
        onPageFinished:(_) {
          if (mounted) setState(() => _loading=false);
        },
        onWebResourceError:(error) {
          if(error.isForMainFrame != false && mounted) {
            setState(() {_loading=false;_failed=true;});
          }
        },
        onNavigationRequest:(request) {
          final uri=Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme=='about') return NavigationDecision.navigate;
          // A JavaScript native bridge is exposed; do not follow other HTTPS
          // origins in this WebView. External links open via the browser.
          if (uri.scheme=='https' && uri.origin == Uri.parse(yolaWebUrl).origin) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(yolaWebUrl));
  }

  Future<void> _back() async {
    if (!_online) {
      setState(() => _online=true);
      return;
    }
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  Future<void> _retry() async {
    setState(() {_online=true;_failed=false;_loading=true;});
    await _web.loadRequest(Uri.parse(yolaWebUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:false,
      onPopInvokedWithResult:(didPop,_) { if(!didPop) _back(); },
      child:Scaffold(
        backgroundColor:const Color(0xFFF8FAFC),
        body:SafeArea(child:IndexedStack(
          index:_online?0:1,
          children:[
            Stack(children:[
              WebViewWidget(controller:_web),
              if(_loading && !_failed)
                const Align(alignment:Alignment.topCenter,
                  child:LinearProgressIndicator(minHeight:2.5)),
              if(_failed) Positioned.fill(child:ColoredBox(
                color:const Color(0xFFF8FAFC),
                child:Center(child:ConstrainedBox(
                  constraints:const BoxConstraints(maxWidth:430),
                  child:Padding(padding:const EdgeInsets.all(24),
                    child:Column(mainAxisSize:MainAxisSize.min,children:[
                      const Icon(Icons.wifi_off_rounded,
                        color:Color(0xFF12273B),size:48),
                      const SizedBox(height:20),
                      const Text('Online Yola unavailable',
                        style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
                      const SizedBox(height:10),
                      const Text('You can use offline cash sales only if this device has a valid signed Master Control licence, a current offline lease and cached inventory.',
                        textAlign:TextAlign.center),
                      const SizedBox(height:22),
                      FilledButton.icon(onPressed:()=>setState(() {
                          _initialOfflineTab=0;_online=false;
                        }),
                        icon:const Icon(Icons.offline_bolt_outlined),
                        label:const Text('Open licensed offline POS')),
                      const SizedBox(height:10),
                      TextButton(onPressed:_retry,child:const Text('Retry online Yola'))
                    ])))))),
              if(!_failed && !_loading)
                Positioned(right:8,bottom:70,child:Material(
                  elevation:3,
                  borderRadius:BorderRadius.circular(28),
                  color:const Color(0xFFF8FAFC),
                  child:PopupMenuButton<int>(
                    tooltip:'SAGRO Receipts, Quotations and Invoices',
                    itemBuilder:(_)=>const [
                      PopupMenuItem(value:1,child:Text('Receipts')),
                      PopupMenuItem(value:2,child:Text('Quotations')),
                      PopupMenuItem(value:3,child:Text('Invoices')),
                    ],
                    onSelected:(target)=>setState(() {
                      _initialOfflineTab=target==1?1:2;
                      _online=false;
                    }),
                    child:const Padding(
                      padding:EdgeInsets.symmetric(horizontal:14,vertical:12),
                      child:Row(mainAxisSize:MainAxisSize.min,children:[
                        Icon(Icons.description_outlined,size:20),
                        SizedBox(width:7),
                        Text('Documents'),
                      ]),
                    ),
                  ),
                )),
              if(!_failed && !_loading)
                Positioned(right:8,bottom:8,
                  child:FloatingActionButton.small(
                    tooltip:'Licensed offline sales / printer / barcode',
                    heroTag:'offline-yola',
                    backgroundColor:const Color(0xFF12273B),
                    foregroundColor:Colors.white,
                    onPressed:()=>setState(() {
                      _initialOfflineTab=0;_online=false;
                    }),
                    child:const Icon(Icons.offline_bolt_rounded))),
            ]),
            YolaOfflineWorkspace(
              initialTab:_initialOfflineTab,
              onReturnOnline:()=>setState(()=>_online=true),
              onCacheOnlineProducts:_cacheOnlineProducts,
            )
          ],
        )),
      ),
    );
  }
}
