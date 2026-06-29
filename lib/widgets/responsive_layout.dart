import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveLayout({
    super.key,
    required this.child,
    this.maxWidth = 1180,
  });

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= AppBreakpoints.tablet
        ? AppInsets.screenWide
        : AppInsets.screen;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

