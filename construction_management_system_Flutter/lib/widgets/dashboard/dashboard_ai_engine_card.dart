import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_strings.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

/// "Which engine is answering?" strip for the supervisor dashboard.
///
/// Reads ``GET /ai/status`` so a rule-only run (no key, quota exhausted, circuit
/// open) is visible at a glance instead of being mistaken for a model verdict.
/// Diagnostics only: when the call fails the widget collapses to nothing rather
/// than pushing an error state onto the dashboard.
class DashboardAiEngineCard extends StatefulWidget {
  const DashboardAiEngineCard({super.key});

  @override
  State<DashboardAiEngineCard> createState() => _DashboardAiEngineCardState();
}

class _DashboardAiEngineCardState extends State<DashboardAiEngineCard> {
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService().aiStatus();
      if (!mounted) return;
      setState(() {
        _status = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool get _live {
    final circuit = _status?['circuit'];
    final open = circuit is Map ? circuit['open'] == true : false;
    return _status?['enabled'] == true && !open;
  }

  String get _modelLabel {
    final active = _status?['active_model']?.toString();
    if (active != null && active.isNotEmpty) return active;
    final preferred = _status?['preferred_model']?.toString();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 52,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.rLg,
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // No status payload at all (endpoint missing / offline): stay out of the way.
    if (_status == null) return const SizedBox.shrink();

    final live = _live;
    final accent = live ? AppColors.green : AppColors.textSecondary;
    final tint = live ? AppColors.greenLight : AppColors.borderLight;
    final headline = live ? _modelLabel : AppStrings.t('dash.aiEngineRuleOnly');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Text(
            AppStrings.t('dash.aiEngine'),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: tint, borderRadius: AppRadius.rPill),
            child: Text(
              live
                  ? AppStrings.t('dash.aiEngineOnline')
                  : AppStrings.t('dash.aiEngineDegraded'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
