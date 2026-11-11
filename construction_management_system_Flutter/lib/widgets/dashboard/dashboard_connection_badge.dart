import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Connection health of the live dashboard feed.
///
/// [live] may only be shown once a real refresh has succeeded — the badge
/// starts in [reconnecting] so a cold start never claims "Live" before any
/// data arrived. Two consecutive failures flip it to [offline].
enum DashboardConnState { live, reconnecting, offline }

/// Small strip that tells a supervisor how trustworthy the numbers below are:
/// the connection state plus the timestamp of the last successful refresh.
///
/// Spec E2 (Live / Reconnecting / Offline + Last Updated) — it must be
/// readable at a glance on a phone, so it stays one line, no animation.
class DashboardConnectionBadge extends StatelessWidget {
  final DashboardConnState state;
  final DateTime? lastUpdated;
  final VoidCallback? onRefresh;

  const DashboardConnectionBadge({
    super.key,
    required this.state,
    this.lastUpdated,
    this.onRefresh,
  });

  Color get _dot => switch (state) {
        DashboardConnState.live => AppColors.green,
        DashboardConnState.reconnecting => AppColors.yellow,
        DashboardConnState.offline => AppColors.red,
      };

  String get _label => switch (state) {
        DashboardConnState.live => 'Live',
        DashboardConnState.reconnecting => 'Reconnecting',
        DashboardConnState.offline => 'Offline',
      };

  String get _hint => switch (state) {
        DashboardConnState.live => 'Data is up to date',
        DashboardConnState.reconnecting => 'Trying to reach the server',
        DashboardConnState.offline => 'No connection — numbers may be stale',
      };

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final last = lastUpdated;
    final updatedText = last == null
        ? 'Last updated: not yet'
        : 'Last updated: ${_fmt(last)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Status dot — colour carries the meaning, the word confirms it.
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            _label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$updatedText · $_hint',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onRefresh != null)
            InkWell(
              onTap: onRefresh,
              borderRadius: AppRadius.rSm,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
