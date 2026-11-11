import 'package:flutter/foundation.dart';

/// Global in-memory bus that notifies listeners whenever a task's mutable
/// state (status etc.) is changed from any page.
///
/// TasksPage listens to this so the main task list refreshes even when the
/// change happened on another page (e.g. ProjectDetailPage quick status
/// buttons). The supervisor pages live in an IndexedStack inside HomeShell,
/// so initState does not run again when the user switches back to Tasks —
/// without a cross-page signal the list would keep showing the stale status.
class TaskStatusNotifier {
  TaskStatusNotifier._();

  static final Set<VoidCallback> _listeners = {};

  /// Registers a callback that is invoked whenever any task is updated.
  static void addListener(VoidCallback cb) => _listeners.add(cb);

  /// Removes a previously registered callback.
  static void removeListener(VoidCallback cb) => _listeners.remove(cb);

  /// Fires all registered callbacks. Safe to call when no one is listening.
  static void notify() {
    final snapshot = List<VoidCallback>.from(_listeners);
    for (final cb in snapshot) {
      cb();
    }
  }
}
