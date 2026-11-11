import 'package:flutter/material.dart';

import 'dashboard/dashboard_connection_badge.dart';

/// Worker-side wrapper around [DashboardConnectionBadge] (spec E2 / item 8).
///
/// The three live worker modules (tasks, attendance, common tasks) each own a
/// different loading flag, so the state is derived from those flags instead of
/// duplicating polling logic in every screen.
class WorkerLiveBadge extends StatelessWidget {
  /// Last refresh failed.
  final bool failed;

  /// A refresh is in flight while earlier data is still on screen.
  final bool loading;

  final DateTime? lastUpdated;
  final VoidCallback? onRefresh;

  const WorkerLiveBadge({
    super.key,
    this.failed = false,
    this.loading = false,
    this.lastUpdated,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final state = failed
        ? DashboardConnState.offline
        : (loading ? DashboardConnState.reconnecting : DashboardConnState.live);
    return DashboardConnectionBadge(
      state: state,
      lastUpdated: lastUpdated,
      onRefresh: onRefresh,
    );
  }
}
