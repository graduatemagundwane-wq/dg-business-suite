import 'package:flutter/material.dart';

import '../auth/activation_service.dart';
import '../auth/auth_repository.dart';
import '../session/app_session.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/primary_button.dart';
import 'activation_screen.dart';
import 'home_screen.dart';

enum _AuthMode {
  onboarding,
  businessRegistration,
  customerRegistration,
  login,
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    if (!session.isAuthenticated) {
      return const ProductionAuthScreen();
    }

    if (session.mustActivateBusiness) {
      return const ActivationScreen();
    }

    return HomeScreen(isOwner: session.isOwner);
  }
}

class ProductionAuthScreen extends StatefulWidget {
  const ProductionAuthScreen({super.key});

  @override
  State<ProductionAuthScreen> createState() => _ProductionAuthScreenState();
}

class _ProductionAuthScreenState extends State<ProductionAuthScreen> {
  final AuthRepository _authRepository = const AuthRepository();

  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _businessPhoneController = TextEditingController();
  final TextEditingController _businessEmailController = TextEditingController();
  final TextEditingController _countryController =
      TextEditingController(text: 'Zimbabwe');
  final TextEditingController _currencyController =
      TextEditingController(text: 'USD');
  final TextEditingController _businessTypeController = TextEditingController();
  final TextEditingController _logoController = TextEditingController();
  final TextEditingController _businessAddressController =
      TextEditingController();
  final TextEditingController _gpsController = TextEditingController();
  final TextEditingController _taxNumberController = TextEditingController();

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _customerEmailController = TextEditingController();
  final TextEditingController _customerLocationController =
      TextEditingController();
  final TextEditingController _favouriteAreaController =
      TextEditingController();

  final TextEditingController _ownerCodeController = TextEditingController();
  final TextEditingController _employeeCodeController = TextEditingController();
  final TextEditingController _loginCustomerPhoneController =
      TextEditingController();

  _AuthMode _mode = _AuthMode.onboarding;
  int _loginRole = 0;
  bool _notificationsEnabled = true;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _countryController.dispose();
    _currencyController.dispose();
    _businessTypeController.dispose();
    _logoController.dispose();
    _businessAddressController.dispose();
    _gpsController.dispose();
    _taxNumberController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _customerLocationController.dispose();
    _favouriteAreaController.dispose();
    _ownerCodeController.dispose();
    _employeeCodeController.dispose();
    _loginCustomerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _registerBusiness(AppSession session) async {
    if (_businessNameController.text.trim().isEmpty ||
        _ownerNameController.text.trim().isEmpty ||
        _businessPhoneController.text.trim().isEmpty) {
      setState(() => _message = 'Business name, owner name and phone are required.');
      return;
    }

    await _run(() async {
      final result = await _authRepository.registerBusiness(
        businessName: _businessNameController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        phone: _businessPhoneController.text.trim(),
        email: _businessEmailController.text.trim(),
        country: _countryController.text.trim(),
        currency: _currencyController.text.trim(),
        businessType: _businessTypeController.text.trim(),
        logoPath: _logoController.text.trim(),
        businessAddress: _businessAddressController.text.trim(),
        gpsLocation: _gpsController.text.trim(),
        taxNumber: _taxNumberController.text.trim(),
      );
      final shop = await _authRepository.loginOwner(
        (result['shop_code'] ?? '').toString(),
      );
      if (shop == null) {
        throw StateError('Business account was created but could not be opened.');
      }

      session.signInOwner(
        shopId: shop['id'] as int,
        ownerName: (shop['owner_name'] ?? _ownerNameController.text).toString(),
        shopName: (shop['shop_name'] ?? _businessNameController.text).toString(),
        activated: false,
        activationStatus: ActivationStatus.pending,
        shopCode: (shop['shop_code'] ?? '').toString(),
      );
    });
  }

  Future<void> _registerCustomer(AppSession session) async {
    if (_customerNameController.text.trim().isEmpty ||
        _customerPhoneController.text.trim().isEmpty) {
      setState(() => _message = 'Name and phone are required.');
      return;
    }

    await _run(() async {
      final customer = await _authRepository.loginCustomer(
        customerName: _customerNameController.text.trim(),
        phoneNumber: _customerPhoneController.text.trim(),
        email: _customerEmailController.text.trim(),
        location: _customerLocationController.text.trim(),
        favouriteArea: _favouriteAreaController.text.trim(),
        notificationsEnabled: _notificationsEnabled,
      );

      session.signInCustomer(
        customerId: customer['id'] as int,
        customerName: (customer['customer_name'] ?? '').toString(),
      );
    });
  }

  Future<void> _login(AppSession session) async {
    await _run(() async {
      if (_loginRole == 0) {
        final shop = await _authRepository.loginOwner(_ownerCodeController.text);
        if (shop == null) throw StateError('Business account was not found.');
        final status = await _authRepository.resolveActivationStatus(shop);
        session.signInOwner(
          shopId: shop['id'] as int,
          ownerName: (shop['owner_name'] ?? 'Owner').toString(),
          shopName: (shop['shop_name'] ?? 'Business').toString(),
          activated: status.allowsBusinessAccess,
          activationStatus: status,
          shopCode: (shop['shop_code'] ?? '').toString(),
        );
      } else if (_loginRole == 1) {
        final employee = await _authRepository.loginEmployee(
          _employeeCodeController.text,
        );
        if (employee == null) {
          throw StateError('Employee account was not found or is inactive.');
        }
        final shopId = employee['shop_id'] as int;
        final shop = await _authRepository.getShopById(shopId);
        final status = await _authRepository.resolveActivationStatus(shop);
        session.signInEmployee(
          shopId: shopId,
          employeeId: employee['id'] as int,
          employeeName: (employee['employee_name'] ?? 'Employee').toString(),
          shopName: (shop?['shop_name'] ?? 'Business').toString(),
          activated: status.allowsBusinessAccess,
          activationStatus: status,
          shopCode: (shop?['shop_code'] ?? '').toString(),
        );
      } else {
        final customer = await _authRepository.loginCustomer(
          customerName: _loginCustomerPhoneController.text.trim(),
          phoneNumber: _loginCustomerPhoneController.text.trim(),
        );
        session.signInCustomer(
          customerId: customer['id'] as int,
          customerName: (customer['customer_name'] ?? 'Customer').toString(),
        );
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppInsets.screen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: DashboardCard(
                child: AnimatedSwitcher(
                  duration: AppDurations.normal,
                  child: _content(session),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(AppSession session) {
    return Column(
      key: ValueKey(_mode),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome to Double Gee Tech',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _subtitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_mode == _AuthMode.onboarding) _onboarding()
        else if (_mode == _AuthMode.businessRegistration) _businessForm(session)
        else if (_mode == _AuthMode.customerRegistration) _customerForm(session)
        else _loginForm(session),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _onboarding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => setState(() => _mode = _AuthMode.businessRegistration),
          icon: const Icon(Icons.storefront),
          label: const Text('Register Business'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => setState(() => _mode = _AuthMode.customerRegistration),
          icon: const Icon(Icons.shopping_bag),
          label: const Text('Join Marketplace'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: () => setState(() => _mode = _AuthMode.login),
          child: const Text('I already have an account'),
        ),
      ],
    );
  }

  Widget _businessForm(AppSession session) {
    return Column(
      children: [
        _field(_businessNameController, 'Business Name', Icons.store),
        _field(_ownerNameController, 'Owner Name', Icons.person),
        _field(_businessPhoneController, 'Phone', Icons.phone),
        _field(_businessEmailController, 'Email', Icons.email),
        _field(_countryController, 'Country', Icons.public),
        _field(_currencyController, 'Currency', Icons.payments),
        _field(_businessTypeController, 'Business Type', Icons.category),
        _field(_logoController, 'Logo Path', Icons.image),
        _field(_businessAddressController, 'Business Address', Icons.location_on),
        _field(_gpsController, 'GPS Location', Icons.my_location),
        _field(_taxNumberController, 'Tax Number Optional', Icons.badge),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Create Shop',
          icon: Icons.add_business,
          isLoading: _loading,
          onPressed: () => _registerBusiness(session),
        ),
        TextButton(
          onPressed: () => setState(() => _mode = _AuthMode.onboarding),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _customerForm(AppSession session) {
    return Column(
      children: [
        _field(_customerNameController, 'Name', Icons.person),
        _field(_customerPhoneController, 'Phone', Icons.phone),
        _field(_customerEmailController, 'Email', Icons.email),
        _field(_customerLocationController, 'Location', Icons.location_on),
        _field(_favouriteAreaController, 'Favourite Shopping Area', Icons.place),
        SwitchListTile(
          value: _notificationsEnabled,
          onChanged: (value) => setState(() => _notificationsEnabled = value),
          title: const Text('Allow Notifications'),
          secondary: const Icon(Icons.notifications_active),
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Join Marketplace',
          icon: Icons.shopping_bag,
          isLoading: _loading,
          onPressed: () => _registerCustomer(session),
        ),
        TextButton(
          onPressed: () => setState(() => _mode = _AuthMode.onboarding),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _loginForm(AppSession session) {
    return Column(
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Owner')),
            ButtonSegment(value: 1, label: Text('Employee')),
            ButtonSegment(value: 2, label: Text('Customer')),
          ],
          selected: {_loginRole},
          onSelectionChanged: (value) => setState(() => _loginRole = value.first),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loginRole == 0)
          _field(_ownerCodeController, 'Business Code', Icons.store)
        else if (_loginRole == 1)
          _field(_employeeCodeController, 'Employee Code', Icons.badge)
        else
          _field(_loginCustomerPhoneController, 'Customer Phone', Icons.phone),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Sign In',
          icon: Icons.login,
          isLoading: _loading,
          onPressed: () => _login(session),
        ),
        TextButton(
          onPressed: () => setState(() => _mode = _AuthMode.onboarding),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.onboarding:
        return 'Create a business workspace or join the marketplace.';
      case _AuthMode.businessRegistration:
        return 'Register your business for activation and cloud services.';
      case _AuthMode.customerRegistration:
        return 'Create your customer marketplace account.';
      case _AuthMode.login:
        return 'Sign in with your account credentials.';
    }
  }
}
