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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── KPI Cards Row ──
          _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, present, late),
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
        ],
      ),
    );
  }

  // ── KPI row builder ──
  Widget _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, present, late) {
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 600;
      final cards = [
        _kpiCard(
          label: 'Workers On Site',
          value: '$onSite/$totalWorkers',
          sub: '${present > 0 ? '${late > 0 ? '$late late' : '0 late'}' : '0 late'} • ${(totalWorkers - onSite)} absent',
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
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
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
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis),
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
          Text(sub, style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted)),
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
                style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
          ]),
          TextButton(
            onPressed: () {},
            child: Text('View All →',
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.accent, fontWeight: FontWeight.w700)),
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
            style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
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
        Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary))),
        Text(pct, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ]);

  Widget _sectionHeader(String title, {String? sub}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (sub != null) Text(sub, style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
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
}
