import 'package:flutter/material.dart';

import '../auth/activation_service.dart';
import '../auth/auth_repository.dart';
import '../services/update_service.dart';
import '../session/app_session.dart';
import '../theme/app_tokens.dart';
import '../widgets/api_error_dialog.dart';
import '../widgets/yola_branding.dart';
import 'activation_screen.dart';
import 'home_screen.dart';

enum _AuthMode {
  onboarding,
  businessRegistration,
  customerRegistration,
  login,
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthRepository _authRepository = const AuthRepository();
  Future<bool>? _restoreFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreFuture ??=
        _authRepository.restoreRemoteSession(SessionScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    if (!session.isAuthenticated) {
      return FutureBuilder<bool>(
        future: _restoreFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (!session.isAuthenticated) {
            return const ProductionAuthScreen();
          }

          return _AuthenticatedHome(session: session);
        },
      );
    }

    return _AuthenticatedHome(session: session);
  }
}

class _AuthenticatedHome extends StatelessWidget {
  final AppSession session;

  const _AuthenticatedHome({
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
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
  final TextEditingController _businessPhoneController =
      TextEditingController();
  final TextEditingController _businessEmailController =
      TextEditingController();
  final TextEditingController _businessPasswordController =
      TextEditingController();
  final TextEditingController _businessConfirmPasswordController =
      TextEditingController();
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
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerEmailController =
      TextEditingController();
  final TextEditingController _customerPasswordController =
      TextEditingController();
  final TextEditingController _customerConfirmPasswordController =
      TextEditingController();
  final TextEditingController _customerLocationController =
      TextEditingController();
  final TextEditingController _favouriteAreaController =
      TextEditingController();

  final TextEditingController _ownerCodeController = TextEditingController();
  final TextEditingController _employeeCodeController = TextEditingController();
  final TextEditingController _loginCustomerPhoneController =
      TextEditingController();
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();

  _AuthMode _mode = _AuthMode.onboarding;
  int _loginRole = 0;
  bool _notificationsEnabled = true;
  bool _businessTermsAccepted = false;
  bool _customerTermsAccepted = false;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _businessPasswordController.dispose();
    _businessConfirmPasswordController.dispose();
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
    _customerPasswordController.dispose();
    _customerConfirmPasswordController.dispose();
    _customerLocationController.dispose();
    _favouriteAreaController.dispose();
    _ownerCodeController.dispose();
    _employeeCodeController.dispose();
    _loginCustomerPhoneController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerBusiness(AppSession session) async {
    if (_businessNameController.text.trim().isEmpty ||
        _ownerNameController.text.trim().isEmpty ||
        _businessPhoneController.text.trim().isEmpty ||
        _businessEmailController.text.trim().isEmpty ||
        _businessPasswordController.text.isEmpty) {
      setState(() => _message =
          'Business name, owner name, phone, email and password are required.');
      return;
    }
    if (_businessPasswordController.text !=
        _businessConfirmPasswordController.text) {
      setState(() => _message = 'Passwords do not match.');
      return;
    }
    if (!_businessTermsAccepted) {
      setState(() => _message =
          'Accept the Terms of Service and Privacy Policy to continue.');
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
        password: _businessPasswordController.text,
        passwordConfirmation: _businessConfirmPasswordController.text,
      );
      final restored = await _authRepository.restoreRemoteSession(session);
      if (restored) return;

      final shop = await _authRepository.loginOwner(
        (result['shop_code'] ?? '').toString(),
      );
      if (shop == null) {
        throw StateError(
            'Business account was created but could not be opened.');
      }

      session.signInOwner(
        shopId: shop['id'] as int,
        ownerName: (shop['owner_name'] ?? _ownerNameController.text).toString(),
        shopName:
            (shop['shop_name'] ?? _businessNameController.text).toString(),
        activated: false,
        activationStatus: ActivationStatus.pending,
        shopCode: (shop['shop_code'] ?? '').toString(),
      );
    });
  }

  Future<void> _registerCustomer(AppSession session) async {
    if (_customerNameController.text.trim().isEmpty ||
        _customerPhoneController.text.trim().isEmpty ||
        _customerEmailController.text.trim().isEmpty ||
        _customerPasswordController.text.isEmpty) {
      setState(
          () => _message = 'Name, phone, email and password are required.');
      return;
    }
    if (_customerPasswordController.text !=
        _customerConfirmPasswordController.text) {
      setState(() => _message = 'Passwords do not match.');
      return;
    }
    if (!_customerTermsAccepted) {
      setState(() => _message =
          'Accept the Terms of Service and Privacy Policy to continue.');
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
        password: _customerPasswordController.text,
        passwordConfirmation: _customerConfirmPasswordController.text,
      );
      final restored = await _authRepository.restoreRemoteSession(session);
      if (restored) return;

      session.signInCustomer(
        customerId: customer['id'] as int,
        customerName: (customer['customer_name'] ?? '').toString(),
      );
    });
  }

  Future<void> _login(AppSession session) async {
    await _run(() async {
      if (_loginEmailController.text.trim().isNotEmpty &&
          _loginPasswordController.text.isNotEmpty) {
        final credentials = await _authRepository.loginWithEmail(
          email: _loginEmailController.text.trim(),
          password: _loginPasswordController.text,
          role: _roleApiValue,
        );
        _authRepository.applyRemoteSession(session, credentials);
        return;
      }

      if (_loginRole == 0) {
        final shop = await _authRepository.loginOwner(
          _ownerCodeController.text,
          password: _loginPasswordController.text,
        );
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
          password: _loginPasswordController.text,
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
          email: _loginEmailController.text.trim(),
          password: _loginPasswordController.text,
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
      setState(
          () => _message = error.toString().replaceFirst('Bad state: ', ''));
      await ApiErrorDialog.show(context, error: error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= AppBreakpoints.tablet;

            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? AppSpacing.xl : AppSpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _brandPanel(wide: true)),
                            const SizedBox(width: AppSpacing.xxl),
                            Expanded(
                              child: _formPanel(session, maxWidth: 560),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _brandPanel(wide: false),
                            const SizedBox(height: AppSpacing.lg),
                            _formPanel(session),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _brandPanel({required bool wide}) {
    final theme = Theme.of(context);

    return YolaGradientPanel(
      padding: EdgeInsets.all(wide ? AppSpacing.xxl : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        children: [
          const YolaLogoLockup(
            compact: false,
            captionColor: Colors.white,
          ),
          SizedBox(height: wide ? 56 : AppSpacing.xl),
          Text(
            'Manage.\nSell.\nGrow.',
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.04,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'A premium business suite for POS, inventory, reports, customers and marketplace growth.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: const [
              _BrandPill(icon: Icons.point_of_sale, label: 'Sales'),
              _BrandPill(icon: Icons.inventory_2, label: 'Inventory'),
              _BrandPill(icon: Icons.analytics, label: 'Reports'),
              _BrandPill(icon: Icons.verified_user, label: 'Secure'),
            ],
          ),
          if (wide) const Spacer(),
          SizedBox(height: wide ? AppSpacing.xxl : AppSpacing.lg),
          Text(
            'Powered by Double Gee Tech',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanel(AppSession session, {double? maxWidth}) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: AnimatedContainer(
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: LanguageSelectorPlaceholder(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: AppDurations.normal,
              child: _content(session),
            ),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<AppUpdateStatus>(
              future: UpdateService.instance.checkForUpdates(),
              builder: (context, snapshot) {
                return AppVersionUpdateRoom(update: snapshot.data);
              },
            ),
          ],
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
          _title,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _subtitle,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_mode == _AuthMode.onboarding)
          _onboarding()
        else if (_mode == _AuthMode.businessRegistration)
          _businessForm(session)
        else if (_mode == _AuthMode.customerRegistration)
          _customerForm(session)
        else
          _loginForm(session),
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
        _RoleChoiceCard(
          selected: true,
          icon: Icons.storefront,
          title: 'Register Business',
          subtitle: 'Create an owner workspace for sales, inventory and staff.',
          onPressed: () =>
              setState(() => _mode = _AuthMode.businessRegistration),
        ),
        const SizedBox(height: AppSpacing.md),
        _RoleChoiceCard(
          selected: false,
          icon: Icons.shopping_bag,
          title: 'Join Marketplace',
          subtitle: 'Create a customer account for orders and spending tools.',
          onPressed: () =>
              setState(() => _mode = _AuthMode.customerRegistration),
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
        _field(
          _businessPasswordController,
          'Password',
          Icons.lock,
          obscureText: true,
        ),
        _field(
          _businessConfirmPasswordController,
          'Confirm Password',
          Icons.lock_reset,
          obscureText: true,
        ),
        _field(_countryController, 'Country', Icons.public),
        _field(_currencyController, 'Currency', Icons.payments),
        _field(_businessTypeController, 'Business Type', Icons.category),
        _field(_logoController, 'Logo Path', Icons.image),
        _field(
            _businessAddressController, 'Business Address', Icons.location_on),
        _field(_gpsController, 'GPS Location', Icons.my_location),
        _field(_taxNumberController, 'Tax Number Optional', Icons.badge),
        TermsPrivacyConsent(
          value: _businessTermsAccepted,
          onChanged: (value) => setState(() => _businessTermsAccepted = value),
        ),
        const SizedBox(height: AppSpacing.md),
        YolaGradientButton(
          label: 'Create Shop',
          icon: Icons.add_business,
          isLoading: _loading,
          onPressed: () => _registerBusiness(session),
        ),
        const SizedBox(height: AppSpacing.md),
        _authDivider(),
        GoogleSignInPlaceholderButton(
          label: 'Sign up with Google',
          onPressed: _showIdentityProviderPlaceholder,
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
        _field(
          _customerPasswordController,
          'Password',
          Icons.lock,
          obscureText: true,
        ),
        _field(
          _customerConfirmPasswordController,
          'Confirm Password',
          Icons.lock_reset,
          obscureText: true,
        ),
        _field(_customerLocationController, 'Location', Icons.location_on),
        _field(
            _favouriteAreaController, 'Favourite Shopping Area', Icons.place),
        SwitchListTile(
          value: _notificationsEnabled,
          onChanged: (value) => setState(() => _notificationsEnabled = value),
          title: const Text('Allow Notifications'),
          secondary: const Icon(Icons.notifications_active),
        ),
        TermsPrivacyConsent(
          value: _customerTermsAccepted,
          onChanged: (value) => setState(() => _customerTermsAccepted = value),
        ),
        const SizedBox(height: AppSpacing.md),
        YolaGradientButton(
          label: 'Join Marketplace',
          icon: Icons.shopping_bag,
          isLoading: _loading,
          onPressed: () => _registerCustomer(session),
        ),
        const SizedBox(height: AppSpacing.md),
        _authDivider(),
        GoogleSignInPlaceholderButton(
          label: 'Sign up with Google',
          onPressed: _showIdentityProviderPlaceholder,
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
          onSelectionChanged: (value) =>
              setState(() => _loginRole = value.first),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_loginEmailController, 'Email', Icons.email),
        _field(
          _loginPasswordController,
          'Password',
          Icons.lock,
          obscureText: true,
        ),
        if (_loginRole == 0)
          _field(
            _ownerCodeController,
            'Business Code for Offline Fallback',
            Icons.store,
          )
        else if (_loginRole == 1)
          _field(
            _employeeCodeController,
            'Employee Code for Offline Fallback',
            Icons.badge,
          )
        else
          _field(
            _loginCustomerPhoneController,
            'Customer Phone for Offline Fallback',
            Icons.phone,
          ),
        const SizedBox(height: AppSpacing.md),
        YolaGradientButton(
          label: 'Sign In',
          icon: Icons.login,
          isLoading: _loading,
          onPressed: () => _login(session),
        ),
        const SizedBox(height: AppSpacing.md),
        _authDivider(),
        GoogleSignInPlaceholderButton(
          label: 'Sign in with Google',
          onPressed: _showIdentityProviderPlaceholder,
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
    IconData icon, {
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  String get _roleApiValue {
    if (_loginRole == 0) return 'business_owner';
    if (_loginRole == 1) return 'employee';
    return 'customer';
  }

  Widget _authDivider() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('OR'),
          ),
          Expanded(
            child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }

  void _showIdentityProviderPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Google sign-in UI is ready for production identity integration.'),
      ),
    );
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.onboarding:
        return 'What business are you building today?';
      case _AuthMode.businessRegistration:
        return 'Create your business account';
      case _AuthMode.customerRegistration:
        return 'Create your customer account';
      case _AuthMode.login:
        return 'Welcome back';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.onboarding:
        return 'Choose a workspace and continue with Double Gee Tech.';
      case _AuthMode.businessRegistration:
        return 'Register your business for activation and cloud services.';
      case _AuthMode.customerRegistration:
        return 'Create your customer marketplace account.';
      case _AuthMode.login:
        return 'Sign in with your account credentials.';
    }
  }
}

class _BrandPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BrandPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const _RoleChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Ink(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.secondary.withValues(alpha: 0.06)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: selected
                ? theme.colorScheme.secondary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                    theme.colorScheme.secondary.withValues(alpha: 0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
