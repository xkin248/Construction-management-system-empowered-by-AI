import 'package:flutter/widgets.dart';

/// Shared responsive breakpoints for BuildSmart.
///
/// Convention: phone < 600, tablet 600-1024, desktop > 1024.
class AppBreakpoints {
  AppBreakpoints._();

  /// Upper bound of phone screens.
  static const double phone = 600;

  /// Upper bound of tablet screens (>= phone is tablet, > tablet is desktop).
  static const double tablet = 1024;

  /// Navigation switch point shared by supervisor & worker shells:
  /// >= 700 uses the wide (sidebar) layout, < 700 uses the narrow (bottom nav).
  static const double navigation = 700;

  /// Max content width for tablet/desktop layouts to avoid full-bleed rows.
  static const double maxContentWidth = 1200;
}

/// Spacing tokens used to replace scattered padding/margin literals.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Convenient device-type checks based on the current screen width.
extension ResponsiveContext on BuildContext {
  bool get isPhone => MediaQuery.sizeOf(this).width < AppBreakpoints.phone;

  bool get isTablet =>
      MediaQuery.sizeOf(this).width >= AppBreakpoints.phone &&
      MediaQuery.sizeOf(this).width < AppBreakpoints.tablet;

  bool get isDesktop => MediaQuery.sizeOf(this).width >= AppBreakpoints.tablet;
}
