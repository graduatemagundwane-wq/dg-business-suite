import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
void main() { runApp(const DoubleGeePOS()); }
class DoubleGeePOS extends StatelessWidget { const DoubleGeePOS({super.key});
@override Widget build(BuildContext context) { return MaterialApp( debugShowCheckedModeBanner: false, title: 'Double Gee Tech', theme: ThemeData( primarySwatch: Colors.blue, ), home: const HomeScreen(), ); } }
