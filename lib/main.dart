import 'package:flutter/material.dart';
import 'session/app_session.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(DoubleGeePOS(session: AppSession.offlineOwner()));
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
        home: const HomeScreen(),
      ),
    );
  }
}
