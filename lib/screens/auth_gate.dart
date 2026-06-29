import 'package:flutter/material.dart';

import '../auth/activation_service.dart';
import '../auth/auth_repository.dart';
import '../session/app_session.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/primary_button.dart';
import 'activation_screen.dart';
import 'home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    if (!session.isAuthenticated) {
      return const LoginScreen();
    }

    if (session.mustActivateBusiness) {
      return const ActivationScreen();
    }

    return HomeScreen(isOwner: session.isOwner);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthRepository _authRepository = const AuthRepository();
  final TextEditingController _ownerCodeController = TextEditingController();
  final TextEditingController _employeeCodeController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();

  int _selectedIndex = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ownerCodeController.dispose();
    _employeeCodeController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loginOwner(AppSession session) async {
    await _runLogin(() async {
      final shop = await _authRepository.loginOwner(_ownerCodeController.text);
      if (shop == null) {
        throw StateError('Shop account was not found.');
      }

      final status = await _authRepository.resolveActivationStatus(shop);
      session.signInOwner(
        shopId: shop['id'] as int,
        ownerName: (shop['owner_name'] ?? 'Owner').toString(),
        shopName: (shop['shop_name'] ?? 'Double Gee POS').toString(),
        activated: status.allowsBusinessAccess,
        activationStatus: status,
        shopCode: (shop['shop_code'] ?? '').toString(),
      );
    });
  }

  Future<void> _loginEmployee(AppSession session) async {
    await _runLogin(() async {
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
        shopName: (shop?['shop_name'] ?? 'Double Gee POS').toString(),
        activated: status.allowsBusinessAccess,
        activationStatus: status,
        shopCode: (shop?['shop_code'] ?? '').toString(),
      );
    });
  }

  Future<void> _loginCustomer(AppSession session) async {
    await _runLogin(() async {
      final customer = await _authRepository.loginCustomer(
        customerName: _customerNameController.text,
        phoneNumber: _customerPhoneController.text,
      );

      session.signInCustomer(
        customerId: customer['id'] as int,
        customerName: (customer['customer_name'] ?? 'Customer').toString(),
      );
    });
  }

  Future<void> _runLogin(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: AppInsets.screen,
              child: DashboardCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Double Gee Business Suite',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Sign in as owner, employee or customer.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Owner')),
                        ButtonSegment(value: 1, label: Text('Employee')),
                        ButtonSegment(value: 2, label: Text('Customer')),
                      ],
                      selected: {_selectedIndex},
                      onSelectionChanged: (value) {
                        setState(() => _selectedIndex = value.first);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_selectedIndex == 0)
                      _LoginField(
                        controller: _ownerCodeController,
                        label: 'Shop Code',
                        icon: Icons.store,
                      )
                    else if (_selectedIndex == 1)
                      _LoginField(
                        controller: _employeeCodeController,
                        label: 'Employee Code',
                        icon: Icons.badge,
                      )
                    else ...[
                      _LoginField(
                        controller: _customerNameController,
                        label: 'Customer Name',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _LoginField(
                        controller: _customerPhoneController,
                        label: 'Phone Number',
                        icon: Icons.phone,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Continue',
                      icon: Icons.login,
                      isLoading: _loading,
                      onPressed: () {
                        if (_selectedIndex == 0) {
                          _loginOwner(session);
                        } else if (_selectedIndex == 1) {
                          _loginEmployee(session);
                        } else {
                          _loginCustomer(session);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Business accounts require activation. Customers are free.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Remote activation: ${ActivationService.baseUrl}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
