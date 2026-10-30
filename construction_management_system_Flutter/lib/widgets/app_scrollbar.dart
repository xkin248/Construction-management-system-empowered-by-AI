import 'package:flutter/material.dart';

/// Always-visible scrollbar wrapper used by every long list in the app.
///
/// The lists are built lazily (ListView.builder / slivers), so the scroll
/// extent keeps growing while the user scrolls. Binding an explicit
/// [ScrollController] keeps the thumb stable across rebuilds, and
/// `thumbVisibility: true` gives mouse / trackpad users a permanent hint that
/// more rows exist instead of a scrollbar that only flashes on scroll.
class AppScrollbar extends StatelessWidget {
  const AppScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: false,
      thickness: 6,
      radius: const Radius.circular(3),
      child: child,
    );
  }
}
