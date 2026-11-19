import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/barcode_scan.dart';
import '../services/receipt_service.dart';
import 'offline_license.dart';
import 'sagro_documents.dart';
import 'offline_pin.dart';
import 'offline_staff.dart';
import 'offline_store.dart';

const _ink = Color(0xFF12273B);
const _accent = Color(0xFF087A71);
const _background = Color(0xFFF5F7FA);

class YolaOfflineWorkspace extends StatefulWidget {
  final VoidCallback onReturnOnline;
  final Future<int> Function() onCacheOnlineProducts;
  final int initialTab;
  final ValueChanged<bool>? onWorkerAuthChanged;
  const YolaOfflineWorkspace({
    super.key, required this.onReturnOnline,
    required this.onCacheOnlineProducts,
    this.initialTab = 0,
    this.onWorkerAuthChanged,
  });
  @override
  State<YolaOfflineWorkspace> createState() => _YolaOfflineWorkspaceState();
}

class _YolaOfflineWorkspaceState extends State<YolaOfflineWorkspace>
    with WidgetsBindingObserver {
  Timer? _licenceCheck;
  YolaLicenceInfo? _license;
  bool _loading = true, _unlocked = false, _busy = false;
  bool _workerLogin = false;
  SagroCashierSession? _session;
  String? _error, _notice;
  int _pending = 0, _selectedTab = 0;
  final _loginPin = TextEditingController();
  final _workerUser = TextEditingController();
  final _workerPassword = TextEditingController();
  final _newWorkerName = TextEditingController();
  final _newWorkerUser = TextEditingController();
  final _newWorkerPassword = TextEditingController();
  List<Map<String, Object?>> _workers = [];
  List<Map<String, Object?>> _performance = [];
  final _businessId = TextEditingController();
  final _businessName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _newPin = TextEditingController();
  final _cashier = TextEditingController(text:'Owner');
  final _customer = TextEditingController();
  final _search = TextEditingController();
  final _discount = TextEditingController(text:'0');
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _sales = [];
  final Map<String,int> _cart = {};
  ReceiptPaperSize _paper = ReceiptPaperSize.mm80;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    _init();
    _licenceCheck=Timer.periodic(const Duration(minutes:2), (_) => _checkRemote());
  }

  @override
  void didUpdateWidget(covariant YolaOfflineWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _selectedTab = _session?.isAdmin == false ? 0 : widget.initialTab);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkRemote();
  }

  Future<void> _checkRemote({bool force = false}) async {
    if (_license == null || (_busy && !force)) return;
    try {
      final info = await YolaLicence.instance.renewOnlineLease();
      if (mounted) setState(() => _license=info);
    } catch (_) {
      // Network loss is handled by the existing signed offline lease.
      // A recorded suspension or expired lease must immediately lock UI.
      try {
        await YolaLicence.instance.requireActive();
      } catch (e) {
        if (mounted) setState(() {
          _license=null;_unlocked=false;_session=null;_selectedTab=0;
          widget.onWorkerAuthChanged?.call(false);
          _cart.clear();_error=e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _licenceCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for(final controller in [_loginPin,_workerUser,_workerPassword,
      _newWorkerName,_newWorkerUser,_newWorkerPassword,
      _businessId,_businessName,_ownerName,
      _phone,_email,_password,_newPin,_cashier,_customer,_search,_discount]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final info = await YolaLicence.instance.active();
      if (!mounted) return;
      setState(() { _license=info; _error=null;_loading=false; });
    } catch (e) {
      if (mounted) setState(() { _loading=false;_error=e.toString(); });
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy=true;_notice=null;_error=null; });
    try {
      await action();
    } catch(e) {
      if (mounted) setState(() => _error=e.toString().replaceFirst('Bad state: ',''));
    } finally {
      if (mounted) setState(() => _busy=false);
    }
  }

  Future<void> _refresh() async {
    final session = _session;
    if (session == null) throw StateError('Sign in to access offline sales.');
    await SagroStaffAccess.instance.requireCanSell(session);
    final products = session.isAdmin
      ? await YolaOfflineStore.instance.products()
      : await YolaOfflineStore.instance.saleProducts();
    final sales = session.isAdmin
      ? await YolaOfflineStore.instance.sales(session)
      : <Map<String, Object?>>[];
    final pending = session.isAdmin
      ? await YolaOfflineStore.instance.pending() : 0;
    if (mounted) setState(() { _products=products;_sales=sales;_pending=pending; });
  }

  Future<void> _loadStaff() async {
    final admin = _session;
    if (admin == null || !admin.isAdmin) return;
    final workers = await SagroStaffAccess.instance.workers(admin);
    final report = await SagroStaffAccess.instance.performance(admin);
    if (mounted) setState(() { _workers=workers;_performance=report; });
  }

  Future<void> _createWorker() => _act(() async {
    final admin = _session;
    if (admin == null) throw StateError('Admin sign-in required.');
    await SagroStaffAccess.instance.createWorker(admin,
      name:_newWorkerName.text,username:_newWorkerUser.text,
      password:_newWorkerPassword.text);
    _newWorkerName.clear();_newWorkerUser.clear();_newWorkerPassword.clear();
    await _loadStaff();
    if (mounted) setState(() => _notice='Worker account created. They can sign in to Sell only.');
  });

  Future<void> _setWorkerActive(int id, bool active) => _act(() async {
    final admin = _session;
    if (admin == null) throw StateError('Admin sign-in required.');
    await SagroStaffAccess.instance.setWorkerActive(admin,id,active);
    await _loadStaff();
    if (mounted) setState(() => _notice=active?'Worker reactivated.':'Worker disabled.');
  });

  void _lock() {
    widget.onWorkerAuthChanged?.call(false);
    setState(() {
      _unlocked=false;_session=null;_selectedTab=0;
      _cart.clear();_products=[];_sales=[];_workers=[];_performance=[];
      _workerPassword.clear();_loginPin.clear();
    });
  }

  Future<void> _requestActivation() => _act(() async {
    if (_newPin.text.length < 6) throw StateError('Set a 6–12 digit PIN.');
    final code = await YolaLicence.instance.requestApproval(
      existingBusinessId:_businessId.text,
      businessName:_businessName.text,
      ownerName:_ownerName.text,phone:_phone.text,
      email:_email.text,password:_password.text);
    await YolaOfflinePin.instance.registerPending(_newPin.text);
    if (mounted) setState(() => _notice='Request $code submitted. Double Gee Tech approval is required. Check approval when notified.');
  });

  Future<void> _claim() => _act(() async {
    final info = await YolaLicence.instance.claimApproved();
    await YolaOfflinePin.instance.activatePending();
    if (mounted) setState(() { _license=info;_notice='Device activated. Enter offline PIN.'; });
  });

  Future<void> _renew() => _act(() async {
    final info = await YolaLicence.instance.renewOnlineLease();
    if (mounted) {
      setState(() {
        _license=info;
        _notice='Signed offline lease renewed by DG Tech Master Control.';
      });
    }
  });

  Future<void> _unlock() => _act(() async {
    final session = _workerLogin
      ? await SagroStaffAccess.instance.loginWorker(
          _workerUser.text,_workerPassword.text)
      : await SagroStaffAccess.instance.loginAdmin(_loginPin.text);
    _session=session;
    try {
      await _refresh();
    } catch (_) {
      _session=null;
      rethrow;
    }
    if(mounted) setState(() {
      _unlocked=true;_notice=null;
      _selectedTab=session.isAdmin ? widget.initialTab : 0;
    });
    widget.onWorkerAuthChanged?.call(!session.isAdmin);
    _workerPassword.clear();_loginPin.clear();
  });

  Future<void> _import() => _act(() async {
    final admin = _session;
    if (admin == null) throw StateError('Admin sign-in required.');
    await SagroStaffAccess.instance.requireAdmin(admin);
    final n = await widget.onCacheOnlineProducts();
    await _refresh();
    if (mounted) setState(() => _notice='$n products securely cached from your signed-in Yola account.');
  });

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const BarcodeScanScreen()));
    if (code == null || code.trim().isEmpty || !mounted) return;
    final match = _products.where((p) =>
      (p['barcode'] ?? '').toString().trim().toLowerCase() ==
      code.trim().toLowerCase()).toList();
    if (match.isNotEmpty) {
      _add(match.first);
    } else {
      _search.text = code;
      if (mounted) setState(() => _notice='No exact match. Search: $code');
    }
  }

  void _add(Map<String,Object?> product) {
    final id=product['product_id'].toString();
    final already=_cart[id] ?? 0;
    final available=(product['stock_qty'] as num).toInt();
    if(already >= available) {
      setState(() => _error='Insufficient stock for ${product['name']}.');
      return;
    }
    setState(() { _cart[id]=already+1;_error=null; });
  }

  int get _subtotal {
    int cents=0;
    for (final p in _products) {
      cents+=((p['price_cents'] as num).toInt())*(_cart[p['product_id']]??0);
    }
    return cents;
  }
  int get _discountCents {
    final value=double.tryParse(_discount.text.trim()) ?? 0;
    if(!value.isFinite || value < 0) return 0;
    return (value*100).round();
  }
  int get _estimatedTax {
    int tax=0;
    for(final p in _products) {
      final qty=_cart[p['product_id']]??0;
      final net=(p['price_cents'] as num).toInt()*qty;
      final bps=(p['tax_bps'] as num).toInt();
      tax+=(net*bps/10000).round();
    }
    final subtotal=_subtotal;
    if(subtotal<=0) return 0;
    return (tax*(subtotal-_discountCents.clamp(0,subtotal))/subtotal).round();
  }
  int get _estimatedTotal {
    final total=_subtotal-_discountCents+_estimatedTax;
    return total<0 ? 0 : total;
  }

  String _money(int cents) => String.fromCharCode(36) + (cents/100).toStringAsFixed(2);

  Future<void> _checkout() => _act(() async {
    if (_cart.isEmpty) throw StateError('The cart is empty.');
    final discount = (double.tryParse(_discount.text.trim()) ?? -1);
    if (!discount.isFinite || discount < 0) throw StateError('Enter a valid discount.');
    final cents = (discount * 100).round();
    await _checkRemote(force:true);
    await YolaLicence.instance.requireActive();
    final session = _session;
    if (session == null || !_unlocked) throw StateError('Sign in to sell.');
    final result = await YolaOfflineStore.instance.checkout(
      quantities:Map.of(_cart),
      session:session,
      customer:_customer.text,
      discountCents:cents);
    _cart.clear();
    _discount.text='0';
    await _refresh();
    if (mounted) {
      setState(() => _notice='Cash sale ${result['receipt_no']} saved offline. Pending reconciliation with Yola Cloud.');
    }
    // Printing is a separate step: print failures never roll back a paid sale.
    // The receipt remains in local history for reprint or PDF sharing.
  });

  Future<void> _print(int id) => _act(() async {
    final admin = _session;
    if (admin == null) throw StateError('Admin sign-in required.');
    await SagroStaffAccess.instance.requireAdmin(admin);
    await YolaOfflineStore.instance.printReceipt(id,size:_paper);
  });

  Future<void> _sync() => _act(() async {
    final admin = _session;
    if (admin == null) throw StateError('Admin sign-in required.');
    await SagroStaffAccess.instance.requireAdmin(admin);
    final result=await YolaOfflineStore.instance.syncPending();
    await _refresh();
    if (mounted) {
      setState(() => _notice=
        '${result['reconciled']} confirmed by cloud; ${result['remaining']} still on this device. ${result['error']??''}');
    }
  });

  Widget _btn(String label,VoidCallback? press, {bool primary=true, IconData? icon}) =>
    FilledButton.icon(
      onPressed:_busy?null:press,
      style:FilledButton.styleFrom(
        backgroundColor:primary?_accent:_ink,
        minimumSize:const Size(0,48)),
      icon:Icon(icon??Icons.arrow_forward_rounded,size:19),
      label:Text(label));

  Widget _field(TextEditingController c,String title,{bool secret=false,
    TextInputType type=TextInputType.text,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted}) => Padding(
    padding:const EdgeInsets.only(bottom:12),
    child:TextField(controller:c,obscureText:secret,keyboardType:type,
      onChanged:onChanged,onSubmitted:onSubmitted,
      decoration:InputDecoration(labelText:title,border:const OutlineInputBorder(),
        isDense:true,filled:true,fillColor:Colors.white)));

  Widget _card(Widget child) => Card(
    margin:const EdgeInsets.symmetric(vertical:8),
    elevation:0,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),
      side:const BorderSide(color:Color(0xFFE2E8EE))),
    child:Padding(padding:const EdgeInsets.all(18),child:child));

  Widget _activation() => ListView(children:[
    _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Register this Android device',style:TextStyle(fontSize:22,
        fontWeight:FontWeight.w800,color:_ink)),
      const SizedBox(height:8),
      const Text('A Yola business must already be registered. Master Control approval and a signed 72-hour offline lease are required.'),
      const SizedBox(height:18),
      _field(_businessId,'Existing Yola business registration ID'),
      _field(_businessName,'Business name'),
      _field(_ownerName,'Owner name'),
      _field(_phone,'Owner phone'),
      _field(_email,'Yola account email',type:TextInputType.emailAddress),
      _field(_password,'Online account password',secret:true),
      _field(_newPin,'New offline PIN (6–12 digits)',secret:true,
        type:TextInputType.number),
      _btn('Request DG Tech approval',_requestActivation),
      const SizedBox(height:18),
      _btn('Check approved licence',_claim,primary:false,
        icon:Icons.verified_user_outlined),
      const SizedBox(height:10),
      _btn('Renew existing lease online',_renew,primary:false,
        icon:Icons.autorenew_outlined),
      const SizedBox(height:10),
      const Text('Until approval is confirmed, no offline sales are allowed.',
        style:TextStyle(fontSize:12)),
    ]))
  ]);

  Widget _unlockPage() => Center(child:ConstrainedBox(
    constraints:const BoxConstraints(maxWidth:420),
    child:_card(Column(mainAxisSize:MainAxisSize.min,
      crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Icon(Icons.lock_outline_rounded,size:42,color:_accent),
      const SizedBox(height:12),
      Text(_license?.businessName ?? 'Yola',style:const TextStyle(
        fontSize:21,fontWeight:FontWeight.bold,color:_ink)),
      const SizedBox(height:8),
      Text('Offline lease ends ${_license!.offlineUntil.toLocal()}',
        style:const TextStyle(fontSize:12)),
      const SizedBox(height:20),
      if(_workerLogin) ...[
        _field(_workerUser,'Worker username'),
        _field(_workerPassword,'Worker password',secret:true),
      ] else
        _field(_loginPin,'Offline owner PIN',secret:true,
          type:TextInputType.number),
      _btn(_workerLogin?'Sign in to Sell':'Unlock admin POS',_unlock,
        icon:Icons.lock_open_outlined),
      const SizedBox(height:10),
      TextButton(
        onPressed:()=>setState(() { _workerLogin=!_workerLogin;
          _workerPassword.clear();_loginPin.clear(); }),
        child:Text(_workerLogin?'Administrator sign in':'Worker sign in'))
    ]))));

  Widget _sellPage() {
    final term=_search.text.toLowerCase().trim();
    final results=_products.where((p)=>term.isEmpty ||
      [p['name'],p['sku'],p['barcode']].any((v)=>
      (v??'').toString().toLowerCase().contains(term))).toList();
    return ListView(children:[
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Offline cash sales',style:TextStyle(fontSize:22,
          fontWeight:FontWeight.w800,color:_ink)),
        const SizedBox(height:8),
        const Text('Sales and stock changes are saved on this device. Cloud totals update only after reconciliation.'),
        const SizedBox(height:14),
        if(_session?.isAdmin == true) ...[
          _btn('Cache products from signed-in online Yola',_import,
            primary:false,icon:Icons.cloud_download_outlined),
          const SizedBox(height:12),
        ],
        Row(children:[
          Expanded(child:_field(_search,'Search name / SKU / barcode',
            onChanged:(_)=>setState((){}),
            onSubmitted:(value) {
              final barcode=value.trim().toLowerCase();
              for(final p in _products) {
                if((p['barcode']??'').toString().trim().toLowerCase()==barcode &&
                    barcode.isNotEmpty) {
                  _add(p);
                  _search.clear();
                  return;
                }
              }
            })),
          const SizedBox(width:8),
          IconButton(onPressed:_busy?null:_scan,
            tooltip:'Scan camera barcode',
            icon:const Icon(Icons.qr_code_scanner,color:_accent,size:30)),
          IconButton(onPressed:()=>_act(_refresh),
            tooltip:'Search',icon:const Icon(Icons.search)),
        ])
      ])),
      for (final p in results) _card(Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(p['name'].toString(),style:const TextStyle(
            fontWeight:FontWeight.bold,color:_ink)),
          if(_session?.isAdmin == true)
            Text('SKU: ${p['sku']}  •  Stock: ${p['stock_qty']}',
              style:const TextStyle(fontSize:12)),
        ])),
        Text(_money((p['price_cents'] as num).toInt())),
        IconButton(onPressed:_busy?null:()=>_add(p),
          icon:const Icon(Icons.add_circle,color:_accent)),
      ])),
      if(results.isEmpty) _card(const Text('No cached products yet. Connect to Yola and cache inventory before going offline.')),
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Current sale',style:TextStyle(
          fontSize:21,fontWeight:FontWeight.w800,color:_ink)),
        const SizedBox(height:12),
        for(final entry in _cart.entries)
          ListTile(contentPadding:EdgeInsets.zero,dense:true,
            title:Text(_products.where((p)=>p['product_id']==entry.key)
              .map((p)=>p['name'].toString()).firstOrNull ?? entry.key),
            subtitle:Text('Quantity: ${entry.value}'),
            trailing:IconButton(icon:const Icon(Icons.remove_circle_outline),
              onPressed:()=>setState(() {
                if(entry.value<=1){_cart.remove(entry.key);}
                else{_cart[entry.key]=entry.value-1;}
              }))),
        if(_cart.isEmpty) const Text('Cart is empty'),
        const Divider(height:25),
        Text('Subtotal  ${_money(_subtotal)}',
          style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
        Text('Estimated tax  ${_money(_estimatedTax)}'),
        Text('Total  ${_money(_estimatedTotal)}',
          style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:_ink)),
        const SizedBox(height:14),
        Text('Cashier: ${_session?.name ?? 'Not signed in'}',
          style:const TextStyle(fontWeight:FontWeight.w600)),
        _field(_customer,'Customer (optional)'),
        _field(_discount,'Discount USD',
          type:const TextInputType.numberWithOptions(decimal:true),
          onChanged:(_)=>setState((){})),
        const Text('Payment: CASH ONLY (received in person)',
          style:TextStyle(color:_accent,fontWeight:FontWeight.bold)),
        const SizedBox(height:12),
        _btn('Complete offline cash sale',_cart.isEmpty?null:_checkout,
          icon:Icons.point_of_sale_outlined),
      ])),
    ]);
  }

  Widget _history() => ListView(children:[
    _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Receipt printing',style:TextStyle(fontSize:21,
        fontWeight:FontWeight.bold,color:_ink)),
      const Text('Uses the Android print/share service. Install a compatible printer service for your 58/80mm thermal printer.'),
      DropdownButton<ReceiptPaperSize>(value:_paper,
        isExpanded:true,
        items:ReceiptPaperSize.values.map((v)=>DropdownMenuItem(
          value:v,child:Text(v.label))).toList(),
        onChanged:(v){if(v!=null)setState(()=>_paper=v);}),
    ])),
    for(final s in _sales) _card(Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(s['receipt_no'].toString(),style:const TextStyle(
          fontWeight:FontWeight.bold,color:_ink)),
        Text('${s['created_at']}  •  ${s['cashier']}',
          style:const TextStyle(fontSize:11)),
        Text(_money((s['total'] as num).toInt()),style:const TextStyle(
          fontWeight:FontWeight.w700)),
      ])),
      IconButton(onPressed:()=>_print((s['id'] as num).toInt()),
        tooltip:'Print / save PDF',
        icon:const Icon(Icons.print_outlined,color:_accent))
    ])),
    if(_sales.isEmpty) _card(const Text('No offline sales yet.'))
  ]);

  Widget _staffAdminPage() => ListView(children:[
    _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Workers',style:TextStyle(fontSize:22,
        fontWeight:FontWeight.w800,color:_ink)),
      const SizedBox(height:8),
      const Text('Create worker accounts for sales only. Workers cannot view inventory, receipts, quotations, invoices or reports.'),
      const SizedBox(height:16),
      _field(_newWorkerName,'Worker full name'),
      _field(_newWorkerUser,'Worker username'),
      _field(_newWorkerPassword,'Temporary worker password',secret:true),
      _btn('Create worker account',_createWorker,icon:Icons.person_add_alt_1_outlined),
    ])),
    for(final w in _workers) _card(Row(children:[
      const Icon(Icons.person_outline,color:_accent),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(w['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('@${w['username']} • ${w['active']==1?'Active':'Disabled'}',
          style:const TextStyle(fontSize:12)),
      ])),
      TextButton(onPressed:_busy?null:()=>_setWorkerActive(
        (w['id'] as num).toInt(),w['active']!=1),
        child:Text(w['active']==1?'Disable':'Enable')),
    ])),
    _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const Expanded(child:Text('Worker progress',style:TextStyle(
          fontSize:21,fontWeight:FontWeight.w800,color:_ink))),
        IconButton(onPressed:()=>_act(_loadStaff),
          tooltip:'Refresh worker progress',icon:const Icon(Icons.refresh)),
      ]),
      const Text('Sales recorded on this Android device only.',
        style:TextStyle(fontSize:12)),
      if(_performance.isEmpty)
        const Padding(padding:EdgeInsets.symmetric(vertical:12),
          child:Text('No workers have been added yet.')),
      for(final p in _performance) Padding(
        padding:const EdgeInsets.symmetric(vertical:10),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(p['name'].toString(),style:const TextStyle(
            fontSize:16,fontWeight:FontWeight.bold)),
          Text('Today: ${p['today_count']} sales • ${_money((p['today_total'] as num).toInt())}'),
          Text('7 days: ${p['week_count']} sales • ${_money((p['week_total'] as num).toInt())}'),
          Text('30 days: ${p['month_count']} sales • ${_money((p['month_total'] as num).toInt())}'),
          Text('All time: ${p['sales_count']} sales • ${_money((p['sales_total'] as num).toInt())}'),
          if(p['last_sale'] != null)
            Text('Last sale: ${p['last_sale']}',style:const TextStyle(fontSize:11)),
          const Divider(),
        ])),
    ])),
  ]);

  Widget _syncPage() => ListView(children:[
    _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Cloud reconciliation',style:TextStyle(fontSize:22,
        fontWeight:FontWeight.w800,color:_ink)),
      const SizedBox(height:10),
      Text('$_pending pending event(s)',style:const TextStyle(
        fontSize:26,fontWeight:FontWeight.bold,color:_accent)),
      const SizedBox(height:12),
      const Text('The queue is durable on this device. Yola must explicitly confirm cloud stock and ledger reconciliation. HTTP success alone never clears a sale.'),
      const SizedBox(height:18),
      _btn('Retry cloud reconciliation',_sync,icon:Icons.sync_rounded),
      const SizedBox(height:10),
      _btn('Renew signed offline lease',_renew,primary:false,
        icon:Icons.verified_user_outlined),
      const SizedBox(height:10),
      _btn('Return to online Yola',widget.onReturnOnline,
        primary:false,icon:Icons.wifi_rounded),
    ]))
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor:_background,
    appBar:AppBar(
      backgroundColor:_ink,foregroundColor:Colors.white,
      title:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Yola.',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
        Text('POWERED BY DOUBLE GEE TECH',
          style:TextStyle(fontSize:8,letterSpacing:1.3)),
      ]),
      actions:[
        if(!_unlocked || _session?.isAdmin == true)
          IconButton(onPressed:widget.onReturnOnline,
            tooltip:'Online workspace',icon:const Icon(Icons.language)),
        if(_unlocked && _session?.isAdmin == true)
          IconButton(onPressed:()=>_act(() async {
            await _loadStaff();
            if(mounted) setState(() => _selectedTab=4);
          }),tooltip:'Workers and progress',
            icon:const Icon(Icons.people_outline)),
        if(_unlocked && _selectedTab==4)
          IconButton(onPressed:()=>setState(()=>_selectedTab=0),
            tooltip:'Back to sales',icon:const Icon(Icons.arrow_back)),
        if(_unlocked) IconButton(
          tooltip:'Lock offline session',onPressed:_lock,
          icon:const Icon(Icons.lock_outline)),
      ]),
    body:_loading?const Center(child:CircularProgressIndicator()):
      Column(children:[
        if(_busy) const LinearProgressIndicator(minHeight:3),
        if(_error!=null) MaterialBanner(
          content:Text(_error!,style:const TextStyle(fontSize:12)),
          backgroundColor:const Color(0xFFFFEEEE),actions:[
            TextButton(onPressed:()=>setState(()=>_error=null),
              child:const Text('Dismiss'))]),
        if(_notice!=null) MaterialBanner(content:Text(_notice!,
            style:const TextStyle(fontSize:12)),actions:[
          TextButton(onPressed:()=>setState(()=>_notice=null),
            child:const Text('OK'))]),
        Expanded(child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:12),
          child:_license==null?_activation():
            !_unlocked?_unlockPage():
            _session?.isAdmin == true
              ? [_sellPage(),_history(),const SagroDocuments(),
                  _syncPage(),_staffAdminPage()][_selectedTab]
              : _sellPage(),
        )),
      ]),
    bottomNavigationBar: _unlocked && _session?.isAdmin == true &&
        _selectedTab < 4 ? NavigationBar(
      selectedIndex:_selectedTab,
      onDestinationSelected:(i)=>setState(()=>_selectedTab=i),
      destinations:const [
        NavigationDestination(icon:Icon(Icons.point_of_sale),label:'Sell'),
        NavigationDestination(icon:Icon(Icons.receipt_long),label:'Receipts'),
        NavigationDestination(icon:Icon(Icons.description_outlined),label:'Documents'),
        NavigationDestination(icon:Icon(Icons.sync),label:'Sync'),
      ]):null,
  );
}
