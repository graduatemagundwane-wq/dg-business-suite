import 'package:flutter/material.dart';
import 'screens/update_gate.dart';
import 'session/app_session.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DoubleGeePOS(session: AppSession.empty()));
}

class DoubleGeePOS extends StatelessWidget {
  final AppSession session;

  const DoubleGeePOS({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Double Gee Tech',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const UpdateGate(),
      ),
    );
  }
}
