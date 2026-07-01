import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 8;
  static const double xl = 12;
  static const double xxl = 24;
}

class AppElevation {
  static const double flat = 0;
  static const double low = 1;
  static const double medium = 3;
}

class AppBreakpoints {
  static const double tablet = 720;
  static const double desktop = 1100;
}

class AppDurations {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
}

class AppInsets {
  static const EdgeInsets screen = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets screenWide = EdgeInsets.all(AppSpacing.xl);
  static const EdgeInsets card = EdgeInsets.all(AppSpacing.lg);
}
