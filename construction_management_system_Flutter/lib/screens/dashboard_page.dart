import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/charts.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool ld = true;
  Map kpi = {};
  Map attSummary = {};
  List projects = [];
  Map<int, Map> _predictions = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final results = await Future.wait([
        ApiService().kpi(),
        ApiService().attendanceToday(),
        ApiService().getProjects(),
      ]);
      kpi = results[0] as Map;
      attSummary = results[1] as Map;
      projects = results[2] as List;

      // Load AI predictions for each project
      final api = ApiService();
      final preds = <int, Map>{};
      await Future.wait(projects.take(4).map((p) async {
        try {
          final pid = p['project_id'] as int;
          preds[pid] = await api.getProjectProgressPrediction(pid);
        } catch (_) {}
      }));
      _predictions = preds;
    } catch (e) {
      toast('Failed to load dashboard: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) {
      return const Center(child: CircularProgressIndicator());
    }

    final onSite = kpi['today_attendance'] ?? 0;
    final totalWorkers = kpi['total_workers'] ?? 0;
    final activeTasks = kpi['pending_tasks'] ?? 0;
    final productivity = kpi['productivity'] ?? 76;
    final alerts = kpi['open_issues'] ?? 0;
    final present = (attSummary['present'] ?? 0) as int;
    final late = (attSummary['late'] ?? 0) as int;
    final absent = (attSummary['absent'] ?? 0) as int;

    // Weekly attendance mock data (Mon-Today)
    final weeklyData = [44.0, 46.0, 43.0, 45.0, 44.0, 42.0, 45.0];
    final weekLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Today'];

    // Task distribution from KPI
    final completed = (kpi['completed_tasks'] ?? 0) as int;
    final inProgress = (kpi['in_progress_tasks'] ?? 0) as int;
    final pending = (kpi['pending_tasks'] ?? 0) as int;
    final totalTasks = completed + inProgress + pending;
    final completedPct = totalTasks > 0 ? (completed / totalTasks * 100).toInt() : 42;
    final inProgressPct = totalTasks > 0 ? (inProgress / totalTasks * 100).toInt() : 33;
    final pendingPct = totalTasks > 0 ? (pending / totalTasks * 100).toInt() : 25;
    final upcoming = _upcomingProjects();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── KPI Cards Row ──
          _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, present, late, absent),
          const SizedBox(height: 20),

          // ── Charts Row ──
          LayoutBuilder(builder: (ctx, cs) {
            final isWide = cs.maxWidth > 600;
            if (isWide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: _weeklyAttCard(weeklyData, weekLabels)),
                const SizedBox(width: 16),
                SizedBox(width: 240, child: _taskDistCard(completedPct, inProgressPct, pendingPct)),
              ]);
            }
            return Column(children: [
              _weeklyAttCard(weeklyData, weekLabels),
              const SizedBox(height: 16),
              _taskDistCard(completedPct, inProgressPct, pendingPct),
            ]);
          }),
          const SizedBox(height: 20),

          // ── Productivity by Project ──
          _sectionHeader('Productivity Trend by Project', sub: 'Weekly task completion rate (%)'),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No projects yet', style: TextStyle(color: AppColors.textMuted))))
          else
            ...projects.take(4).map((p) => _projectProductivityRow(p)),
          const SizedBox(height: 24),

          // ── Upcoming Due Projects ──
          _sectionHeader('Upcoming Due Projects', sub: 'Projects due within 30 days or overdue'),
          const SizedBox(height: 12),
          if (upcoming.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('无临近到期项目', style: TextStyle(color: AppColors.textMuted))))
          else
            ...upcoming.map((p) => _upcomingProjectCard(p)),
          const SizedBox(height: 24),

          // ── AI Site Progress Prediction ──
          if (_predictions.isNotEmpty) ...[
            _sectionHeader('AI Site Progress Prediction', sub: 'Gemini-powered forecast of project completion trajectories'),
            const SizedBox(height: 12),
            ...projects.take(4).where((p) => _predictions.containsKey(p['project_id'])).map((p) => _aiPredictionCard(p)),
          ],
        ],
      ),
    );
  }

  // ── KPI row builder ──
  Widget _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, present, late, absent) {
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 600;
      final cards = [
        _kpiCard(
          label: 'Workers On Site',
          value: '$onSite/$totalWorkers',
          sub: '$late late • $absent absent',
          icon: Icons.groups_rounded,
          iconColor: AppColors.accent,
        ),
        _kpiCard(
          label: 'Active Tasks',
          value: '$activeTasks',
          sub: '2 completed today',
          icon: Icons.assignment_rounded,
          iconColor: AppColors.blue,
        ),
        _kpiCard(
          label: 'Overall Productivity',
          value: '$productivity%',
          sub: '+4% from last week',
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
        _kpiCard(
          label: 'Alerts',
          value: '$alerts',
          sub: '2 attendance • 1 safety',
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.red,
        ),
      ];

      if (isWide) {
        return Row(children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: 14)]).toList()..removeLast());
      }
      return Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ]);
    });
  }

  Widget _kpiCard({required String label, required String value, String? sub, required IconData icon, required Color iconColor, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(label,
                maxLines: 2,
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ]),
        const SizedBox(height: 10),
        Text(value,
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary)),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
        ],
      ]),
    );
  }

  // ── Weekly Attendance Chart Card ──
  Widget _weeklyAttCard(List<double> data, List<String> labels) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Weekly Attendance',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text('All projects combined',
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ]),
          TextButton(
            onPressed: () {},
            child: Text('View All →',
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        LabeledBarChart(values: data, labels: labels, height: 140, color: AppColors.blue.withValues(alpha: 0.25), highlightColor: AppColors.blue),
      ]),
    );
  }

  // ── Task Distribution Donut Card ──
  Widget _taskDistCard(int completedPct, int inProgressPct, int pendingPct) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Task Distribution',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        Text('All active projects',
            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Center(
          child: SimpleDonutChart(
            size: 110,
            slices: [
              DonutSlice(completedPct.toDouble(), AppColors.green, 'Completed'),
              DonutSlice(inProgressPct.toDouble(), AppColors.accent, 'In Progress'),
              DonutSlice(pendingPct.toDouble(), AppColors.border, 'Pending'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _legendRow('Completed', '$completedPct%', AppColors.green),
        const SizedBox(height: 6),
        _legendRow('In Progress', '$inProgressPct%', AppColors.accent),
        const SizedBox(height: 6),
        _legendRow('Pending', '$pendingPct%', AppColors.textMuted),
      ]),
    );
  }

  Widget _legendRow(String label, String pct, Color color) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary))),
        Text(pct, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ]);

  Widget _sectionHeader(String title, {String? sub}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (sub != null) Text(sub, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
      ]);

  Widget _projectProductivityRow(Map p) {
    final progress = (p['progress'] as num? ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(p['project_name'] ?? '-',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),
          Text('${progress.toStringAsFixed(0)}%',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress / 100,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
      ]),
    );
  }

  // ── Upcoming Due Projects ──
  List _upcomingProjects() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = projects.where((p) {
      final status = (p['status'] as String? ?? '').toLowerCase();
      if (status == 'completed' || status == 'done') return false;
      final end = DateTime.tryParse((p['end_date'] as String?) ?? '');
      if (end == null) return false;
      final endDay = DateTime(end.year, end.month, end.day);
      return endDay.difference(today).inDays <= 30;
    }).toList();
    due.sort((a, b) {
      final da = DateTime.tryParse((a['end_date'] as String?) ?? '') ?? DateTime(9999);
      final db = DateTime.tryParse((b['end_date'] as String?) ?? '') ?? DateTime(9999);
      return da.compareTo(db);
    });
    return due;
  }

  Widget _upcomingProjectCard(Map p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime.tryParse((p['end_date'] as String?) ?? '');
    int daysLeft = 0;
    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      daysLeft = endDay.difference(today).inDays;
    }
    final overdue = daysLeft < 0;
    final dueToday = daysLeft == 0;
    final label = overdue ? '已逾期 ${-daysLeft} 天' : (dueToday ? '今天到期' : '剩 $daysLeft 天');
    final color = overdue ? AppColors.red : (dueToday ? AppColors.yellow : AppColors.green);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(overdue ? Icons.event_busy_rounded : (dueToday ? Icons.event_available_rounded : Icons.event_rounded), size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['project_name'] ?? '-', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('Due: ${_fmtDate((p['end_date'] as String?) ?? '')}', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }

  // ── AI Progress Prediction Card ──
  Widget _aiPredictionCard(Map p) {
    final pid = p['project_id'] as int;
    final pred = _predictions[pid]!;
    final trend = pred['trend'] as String? ?? 'on_track';
    final confidence = (pred['confidence'] as num? ?? 70).toDouble();
    final predictedDate = pred['predicted_completion_date'] as String? ?? '-';
    final plannedEnd = pred['planned_end_date'] as String?;
    final insights = pred['ai_insights'] as String? ?? '';
    final milestones = (pred['milestones'] as List?) ?? [];
    final currentProgress = (pred['current_progress'] as num? ?? 0).toDouble();

    final trendColor = switch (trend) {
      'ahead' => AppColors.green,
      'on_track' => AppColors.blue,
      'behind' => AppColors.accent,
      'critical' => AppColors.red,
      _ => AppColors.textMuted,
    };
    final trendLabel = switch (trend) {
      'ahead' => 'Ahead of Schedule',
      'on_track' => 'On Track',
      'behind' => 'Behind Schedule',
      'critical' => 'At Risk — Critical',
      _ => trend,
    };
    final trendIcon = switch (trend) {
      'ahead' => Icons.rocket_launch_rounded,
      'on_track' => Icons.check_circle_rounded,
      'behind' => Icons.warning_rounded,
      'critical' => Icons.error_rounded,
      _ => Icons.help_rounded,
    };

    // Find the 30-day milestone for the prediction bar
    double predProgress = currentProgress;
    for (final m in milestones) {
      if (m['label'] == '30 days') {
        predProgress = (m['predicted_progress'] as num).toDouble();
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: trendColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row: project name + trend badge ──
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(p['project_name'] ?? '-',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: trendColor.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(trendIcon, size: 14, color: trendColor),
              const SizedBox(width: 5),
              Text(trendLabel,
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: trendColor)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),

        // ── AI Insight ──
        if (insights.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(insights,
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ),

        // ── Current vs Predicted Progress Bar ──
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text('${currentProgress.toStringAsFixed(1)}%',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Predicted (30 days)', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text('${predProgress.toStringAsFixed(1)}%',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: trendColor)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('AI Confidence', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text('${confidence.toStringAsFixed(0)}%',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
          ]),
        ]),
        const SizedBox(height: 10),

        // ── Dual Progress Bar (current + predicted) ──
        Stack(
          children: [
            // Predicted (dashed/background) — full width to predProgress
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: predProgress / 100,
                minHeight: 14,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(trendColor.withValues(alpha: 0.25)),
              ),
            ),
            // Current (solid)
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: currentProgress / 100,
                minHeight: 14,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(trendColor),
              ),
            ),
            // Milestone markers
            Positioned.fill(
              child: Row(
                children: milestones.take(3).map((m) {
                  final pct = ((m['predicted_progress'] as num).toDouble()) / 100;
                  return Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment(pct * 2 - 1, 0),
                      child: Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Date rows ──
        Row(children: [
          _dateChip('Planned End', plannedEnd ?? '-', AppColors.textSecondary),
          const SizedBox(width: 10),
          _dateChip('AI Predicted', _fmtDate(predictedDate), trendColor),
          const Spacer(),
          if (confidence >= 80)
            const Icon(Icons.verified_rounded, size: 16, color: AppColors.green)
          else if (confidence >= 60)
            const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
        ]),
      ]),
    );
  }

  Widget _dateChip(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
      Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
    ]);
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
