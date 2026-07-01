import '../database/local_db.dart';
import '../services/api_auth_service.dart';
import '../services/api_credential_store.dart';
import '../services/double_gee_api_service.dart';
import '../session/app_session.dart';
import 'activation_service.dart';
import 'customer_auth.dart';
import 'employee_auth.dart';
import 'owner_auth.dart';

class AuthRepository {
  static const int defaultEmployeeLimit = 5;

  const AuthRepository();

  Future<Map<String, dynamic>?> loginOwner(
    String identifier, {
    String password = '',
  }) async {
    await _tryRemoteLogin(
      role: 'business_owner',
      identifier: identifier.trim(),
      password: password,
    );
    return OwnerAuth.instance.loginShop(identifier.trim());
  }

  Future<Map<String, dynamic>?> loginEmployee(
    String identifier, {
    String password = '',
  }) async {
    await _tryRemoteLogin(
      role: 'employee',
      identifier: identifier.trim(),
      password: password,
    );
    return EmployeeAuth.instance.loginEmployee(identifier.trim());
  }

  Future<Map<String, dynamic>> loginCustomer({
    required String customerName,
    required String phoneNumber,
    String email = '',
    String location = '',
    String favouriteArea = '',
    bool notificationsEnabled = false,
    String password = '',
    String passwordConfirmation = '',
  }) async {
    final isRegistration = customerName.trim() != phoneNumber.trim() ||
        email.trim().isNotEmpty ||
        location.trim().isNotEmpty ||
        favouriteArea.trim().isNotEmpty;

    if (isRegistration) {
      await _tryRemoteRegister(
        accountType: 'customer',
        payload: {
          'name': customerName.trim(),
          'phone': phoneNumber.trim(),
          'email': email.trim(),
          'password': password,
          'password_confirmation': passwordConfirmation,
          'location': location.trim(),
          'favourite_shopping_area': favouriteArea.trim(),
          'notifications_enabled': notificationsEnabled,
        },
      );
    } else {
      await _tryRemoteLogin(
        role: 'customer',
        identifier: phoneNumber.trim(),
        email: email.trim().isNotEmpty ? email.trim() : phoneNumber.trim(),
        password: password,
      );
    }

    return CustomerAuth.instance.findOrCreateCustomer(
      customerName: customerName,
      phoneNumber: phoneNumber,
      email: email,
      location: location,
      favouriteArea: favouriteArea,
      notificationsEnabled: notificationsEnabled,
    );
  }

  Future<Map<String, dynamic>> registerBusiness({
    required String businessName,
    required String ownerName,
    required String phone,
    required String email,
    required String country,
    required String currency,
    required String businessType,
    required String logoPath,
    required String businessAddress,
    required String gpsLocation,
    required String taxNumber,
    required String password,
    required String passwordConfirmation,
  }) async {
    await _tryRemoteRegister(
      accountType: 'business_owner',
      payload: {
        'full_name': ownerName.trim(),
        'business_name': businessName.trim(),
        'owner_name': ownerName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
        'country': country.trim(),
        'currency': currency.trim(),
        'business_type': businessType.trim(),
        'logo_path': logoPath.trim(),
        'business_address': businessAddress.trim(),
        'gps_location': gpsLocation.trim(),
        'tax_number': taxNumber.trim(),
      },
    );

    return OwnerAuth.instance.registerShop(
      shopName: businessName,
      ownerName: ownerName,
      whatsapp: phone,
      email: email,
      country: country,
      currency: currency,
      businessType: businessType,
      logoPath: logoPath,
      businessAddress: businessAddress,
      gpsLocation: gpsLocation,
      taxNumber: taxNumber,
    );
  }

  Future<void> logout() {
    return ApiAuthService.instance.logout();
  }

  Future<ApiCredentials> loginWithEmail({
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      return ApiAuthService.instance.login(
        email: email.trim(),
        password: password,
        role: role,
      );
    } on ApiException catch (error) {
      throw StateError(error.friendlyMessage);
    }
  }

  Future<bool> restoreRemoteSession(AppSession session) async {
    final credentials = await ApiAuthService.instance.restoreSession();
    if (credentials == null) return false;

    applyRemoteSession(session, credentials);
    return true;
  }

  void applyRemoteSession(AppSession session, ApiCredentials credentials) {
    final role = credentials.role;
    final user = credentials.user;
    final displayName = _readString(user, [
          'full_name',
          'name',
          'customer_name',
          'employee_name',
        ]) ??
        'Yola User';
    final businessId = credentials.businessId ??
        _readString(user, ['business_id', 'shop_id', 'company_id']);
    final parsedBusinessId = int.tryParse(businessId ?? '') ?? 1;
    final parsedUserId = int.tryParse(_readString(user, ['id']) ?? '') ?? 1;

    if (role == 'customer') {
      session.signInCustomer(
        customerId: parsedUserId,
        customerName: displayName,
      );
    } else if (role == 'employee') {
      session.signInEmployee(
        shopId: parsedBusinessId,
        employeeId: parsedUserId,
        employeeName: displayName,
        shopName: _readString(user, ['business_name', 'shop_name']) ??
            'Yola Business',
        activated: true,
        activationStatus: ActivationStatus.activated,
        shopCode: businessId ?? '',
      );
    } else {
      session.signInOwner(
        shopId: parsedBusinessId,
        ownerName: displayName,
        shopName: _readString(user, ['business_name', 'shop_name']) ??
            'Yola Business',
        activated: true,
        activationStatus: ActivationStatus.activated,
        shopCode: businessId ?? '',
      );
    }
  }

  Future<Map<String, dynamic>?> getShopById(int shopId) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.query(
      'shops',
      where: 'id = ?',
      whereArgs: [shopId],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  Future<bool> activateShop({
    required String shopCode,
    required String activationCode,
  }) async {
    final remoteStatus = await ActivationService.instance.verifyActivationCode(
      shopCode: shopCode.trim(),
      activationCode: activationCode.trim(),
    );

    if (remoteStatus.allowsBusinessAccess) return true;

    return OwnerAuth.instance.activateShop(
      shopCode: shopCode.trim(),
      activationCode: activationCode.trim(),
    );
  }

  bool shopIsActivated(Map<String, dynamic>? shop) {
    return shop?['activated'] == 1;
  }

  Future<ActivationStatus> resolveActivationStatus(
    Map<String, dynamic>? shop,
  ) async {
    if (shop == null) return ActivationStatus.pending;

    return ActivationService.instance.checkRemoteActivation(
      shopCode: (shop['shop_code'] ?? '').toString(),
      locallyActivated: shopIsActivated(shop),
    );
  }

  Future<void> _tryRemoteLogin({
    required String role,
    required String identifier,
    String email = '',
    String password = '',
  }) async {
    if ((email.isEmpty && identifier.isEmpty) || password.isEmpty) return;

    try {
      await ApiAuthService.instance.login(
        email: email.isNotEmpty ? email : identifier,
        password: password,
        role: role,
        identifier: identifier,
      );
      await ApiAuthService.instance.currentUser();
    } on ApiException catch (error) {
      if (error.canUseOfflineMode) return;
      throw StateError(error.friendlyMessage);
    }
  }

  Future<void> _tryRemoteRegister({
    required String accountType,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await ApiAuthService.instance.register(
        accountType: accountType,
        payload: payload,
      );
      await ApiAuthService.instance.currentUser();
    } on ApiException catch (error) {
      if (error.canUseOfflineMode) return;
      throw StateError(error.friendlyMessage);
    }
  }

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }

    return null;
  }
}
