import 'package:flutter/widgets.dart';

import '../auth/activation_service.dart';

enum AppRole {
  owner,
  employee,
  customer,
}

class AppSession extends ChangeNotifier {
  AppRole? _role;
  int? _shopId;
  int? _employeeId;
  int? _customerId;
  String _displayName;
  String _shopName;
  ActivationStatus _activationStatus;
  String _shopCode;

  AppSession({
    AppRole? role,
    int? shopId,
    int? employeeId,
    int? customerId,
    String displayName = '',
    String shopName = '',
    bool shopActivated = false,
    ActivationStatus? activationStatus,
    String shopCode = '',
  })  : _role = role,
        _shopId = shopId,
        _employeeId = employeeId,
        _customerId = customerId,
        _displayName = displayName,
        _shopName = shopName,
        _activationStatus = activationStatus ??
            (shopActivated
                ? ActivationStatus.activated
                : ActivationStatus.pending),
        _shopCode = shopCode;

  factory AppSession.empty() {
    return AppSession();
  }

  factory AppSession.offlineOwner() {
    return AppSession(
      role: AppRole.owner,
      shopId: 1,
      employeeId: 1,
      displayName: 'Owner',
      shopName: 'Double Gee POS',
      shopActivated: true,
      activationStatus: ActivationStatus.activated,
    );
  }

  AppRole? get role => _role;
  int? get shopId => _shopId;
  int? get employeeId => _employeeId;
  int? get customerId => _customerId;
  String get displayName => _displayName;
  String get shopName => _shopName;
  String get shopCode => _shopCode;
  ActivationStatus get activationStatus => _activationStatus;
  bool get shopActivated => _activationStatus.allowsBusinessAccess;

  bool get isAuthenticated => _role != null;
  bool get isOwner => _role == AppRole.owner;
  bool get isEmployee => _role == AppRole.employee;
  bool get isCustomer => _role == AppRole.customer;
  bool get isBusinessAccount => isOwner || isEmployee;
  bool get mustActivateBusiness => isBusinessAccount && !shopActivated;

  int get requiredShopId => _shopId ?? 1;
  int get requiredEmployeeId => _employeeId ?? 1;

  void signInOwner({
    required int shopId,
    required String ownerName,
    required String shopName,
    required bool activated,
    ActivationStatus? activationStatus,
    String shopCode = '',
  }) {
    _role = AppRole.owner;
    _shopId = shopId;
    _employeeId = null;
    _customerId = null;
    _displayName = ownerName;
    _shopName = shopName;
    _activationStatus = activationStatus ??
        (activated ? ActivationStatus.activated : ActivationStatus.pending);
    _shopCode = shopCode;
    notifyListeners();
  }

  void signInEmployee({
    required int shopId,
    required int employeeId,
    required String employeeName,
    required String shopName,
    required bool activated,
    ActivationStatus? activationStatus,
    String shopCode = '',
  }) {
    _role = AppRole.employee;
    _shopId = shopId;
    _employeeId = employeeId;
    _customerId = null;
    _displayName = employeeName;
    _shopName = shopName;
    _activationStatus = activationStatus ??
        (activated ? ActivationStatus.activated : ActivationStatus.pending);
    _shopCode = shopCode;
    notifyListeners();
  }

  void signInCustomer({
    required int customerId,
    required String customerName,
  }) {
    _role = AppRole.customer;
    _shopId = null;
    _employeeId = null;
    _customerId = customerId;
    _displayName = customerName;
    _shopName = 'Marketplace';
    _activationStatus = ActivationStatus.activated;
    _shopCode = '';
    notifyListeners();
  }

  void updateActivation({
    required ActivationStatus status,
  }) {
    _activationStatus = status;
    notifyListeners();
  }

  void signOut() {
    _role = null;
    _shopId = null;
    _employeeId = null;
    _customerId = null;
    _displayName = '';
    _shopName = '';
    _activationStatus = ActivationStatus.pending;
    _shopCode = '';
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<AppSession> {
  const SessionScope({
    super.key,
    required AppSession session,
    required super.child,
  }) : super(notifier: session);

  static AppSession of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SessionScope>();

    assert(scope != null, 'SessionScope was not found in the widget tree.');
    return scope!.notifier!;
  }
}
