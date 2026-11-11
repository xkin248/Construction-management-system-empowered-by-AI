import 'package:flutter/widgets.dart';

/// Accessibility helpers shared across screens.
///
/// Everything here is stateless and purely semantic: wiring a helper in can
/// never move a pixel, which keeps the visual language untouched.

/// Wraps a custom tap target (InkWell / GestureDetector tree) into one
/// focusable node with a spoken [label].
///
/// [excludeSemantics] is always on: the label is written for the ear, so the
/// raw inner text (names, chips, numbers) must not be read a second time.
Widget semanticTapTarget({
  required String label,
  required Widget child,
  String? hint,
  bool? selected,
}) =>
    Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: label,
      hint: hint,
      selected: selected,
      child: child,
    );

/// Marks an icon-only control that has no [Tooltip] of its own.
Widget semanticIconButton({required String label, required Widget child, String? hint}) =>
    Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: label,
      hint: hint,
      child: child,
    );

/// Announces a status badge as "Status: value" instead of the bare word.
Widget semanticStatus(Widget badge, String status) => Semantics(
      container: true,
      label: 'Status: ${status.replaceAll('_', ' ')}',
      child: ExcludeSemantics(child: badge),
    );
