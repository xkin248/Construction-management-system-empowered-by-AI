import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../services/api_service.dart';
import '../widgets/a11y.dart';

/// Read-only worker profile, opened by tapping a card on the Workers page.
/// Previously the worker cards had no entry point at all (P1 defect).
class WorkerDetailPage extends StatefulWidget {
  final int workerId;
  final Map? initial;
  const WorkerDetailPage({super.key, required this.workerId, this.initial});

  @override
  State<WorkerDetailPage> createState() => _WorkerDetailPageState();
}

class _WorkerDetailPageState extends State<WorkerDetailPage> {
  Map? w;
  bool ld = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    w = widget.initial;
    ld = w == null;
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService().getWorker(widget.workerId);
      if (!mounted) return;
      setState(() {
        w = d;
        ld = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        ld = false;
      });
      toast('Failed to load worker: $e');
    }
  }

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} $h:$m';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (w?['name'] as String?) ?? 'Worker';
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: AppColors.transparent,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(name,
            style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: ld
              ? const SkeletonDetail()
              : (_loadError != null && w == null)
                  ? FailureState(error: _loadError, onRetry: _load)
                  : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      sectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          initialsAvatar(name, radius: 26),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: GoogleFonts.inter(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    Icon(Icons.handyman_outlined,
                                        size: 14,
                                        color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                        (w?['trade'] as String?) ??
                                            'General Worker',
                                        style: GoogleFonts.inter(
                                            fontSize: 13.5,
                                            color: AppColors.textMuted)),
                                  ]),
                                ]),
                          ),
                          semanticStatus(statusPill((w?['today_status'] as String?) ?? 'absent'), (w?['today_status'] as String?) ?? 'absent'),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: statCard(
                            label: 'Hours today',
                            value: w?['hours_today'] == null
                                ? '-'
                                : '${w?['hours_today']}',
                            sub: 'hours',
                            icon: Icons.timer_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: statCard(
                            label: 'Safety training',
                            value: (w?['has_safety_training'] == true)
                                ? 'Done'
                                : 'Pending',
                            sub: (w?['has_safety_training'] == true)
                                ? 'certified'
                                : 'not recorded',
                            icon: Icons.health_and_safety_outlined,
                            iconColor: (w?['has_safety_training'] == true)
                                ? AppColors.green
                                : AppColors.yellow,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _section('Today', [
                        _row(Icons.login_rounded, 'Check-in',
                            _fmt(w?['check_in_time'] as String?)),
                        _row(Icons.logout_rounded, 'Check-out',
                            _fmt(w?['check_out_time'] as String?)),
                        _row(Icons.timer_outlined, 'Hours today',
                            w?['hours_today'] == null
                                ? '-'
                                : '${w?['hours_today']} h'),
                      ]),
                      const SizedBox(height: 12),
                      _section('Profile', [
                        _row(Icons.badge_outlined, 'Worker ID',
                            '${w?['worker_id'] ?? '-'}'),
                        _row(
                            Icons.apartment_rounded,
                            'Project',
                            (w?['project'] is Map
                                ? (w?['project']['project_name'] as String?)
                                : null) ??
                                'Not assigned'),
                        _row(Icons.phone_outlined, 'Phone',
                            (w?['phone'] as String?) ?? '-'),
                        _row(Icons.mail_outline_rounded, 'Email',
                            (w?['email'] as String?) ?? '-'),
                        _row(Icons.credit_card_rounded, 'IC number',
                            (w?['ic_number'] as String?) ?? '-'),
                        _row(
                            Icons.health_and_safety_outlined,
                            'Safety training',
                            (w?['has_safety_training'] == true)
                                ? 'Completed'
                                : 'Not recorded'),
                        _row(
                            Icons.verified_user_outlined,
                            'Safety officer',
                            (w?['is_safety_officer'] == true) ? 'Yes' : 'No'),
                      ]),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => sectionCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ...rows,
        ]),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13.5, color: AppColors.textSecondary)),
          const Spacer(),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ]),
      );
}
