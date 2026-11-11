import 'package:flutter/widgets.dart';

/// Ceiling applied to the OS font scale.
///
/// BuildSmart packs table-like rows, chips and status pills into dense cards;
/// past ~1.3x the OS scale those rows start clipping their labels. The app
/// therefore clamps only the extreme end of the range — anything a user sets
/// at or below 1.3x is honoured untouched.
const double kMaxTextScaleFactor = 1.3;

/// Clamps the platform text scale for the whole app.
///
/// Used as [MaterialApp.builder] so it applies to every route (including
/// dialogs and bottom sheets, which build above the navigator's media query).
class AppTextScaler extends StatelessWidget {
  const AppTextScaler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxTextScaleFactor, child: child);
}
