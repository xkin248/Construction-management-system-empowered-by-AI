import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../widgets/charts.dart';
import '../widgets/add_worker_sheet.dart';
import '../l10n/app_strings.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  @override
  Widget build(BuildContext c) {
    return const _TeamAttendanceTab();
  }
}

// ══════════════════════ Team Attendance Tab ══════════════════════
class _TeamAttendanceTab extends StatefulWidget {
  const _TeamAttendanceTab();

  @override
  State<_TeamAttendanceTab> createState() => _TeamAttendanceTabState();
}

class _TeamAttendanceTabState extends State<_TeamAttendanceTab> {
  bool ld = true;
  Map summary = {};
  List projects = [];
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final results = await Future.wait([
        ApiService().attendanceToday(),
        ProjectCache.get(ApiService()),
      ]);
      summary = results[0] as Map;
      projects = results[1] as List;
    } catch (e) {
      toast('Failed to load attendance: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());

    final total = (summary['total'] ?? 0) as int;
    final present = (summary['present'] ?? 0) as int;
    final late = (summary['late'] ?? 0) as int;
    final absent = (summary['absent'] ?? 0) as int;
    final rows = (summary['rows'] as List?) ?? [];

    // Filter
    final filtered = rows.where((w) {
      final name = (w['name'] as String? ?? '').toLowerCase();
      final status = (w['status'] as String? ?? '').toLowerCase();
      final matchSearch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchStatus = _statusFilter == 'All' || status == _statusFilter.toLowerCase();
      return matchSearch && matchStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Add Worker ──
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => showAddWorkerSheet(context, onAdded: _load),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(AppStrings.t('workers.addWorker'),
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── KPI Summary ──
                _buildKpiRow(total, present, late, absent),
                const SizedBox(height: 16),

                // ── Attendance Rate Bar ──
                _buildAttendanceRateCard(present, late, absent),

                // ── Check-in window notice ──
                if (summary['window_enforced'] == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Check-in window is enforced — workers must check in within the configured time window',
                          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.warning, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Project Geofence Cards ──
                if (projects.isNotEmpty) ...[
                  _sectionLabel("Today's Attendance Rate — All Projects"),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: projects.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _ProjectGeofenceCard(project: projects[i]),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Search + Filter ──
                _buildFilterRow(),
                const SizedBox(height: 10),

                // ── Worker Table ──
                _buildWorkerTable(filtered),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiRow(int total, int present, int late, int absent) {
    final pct = total > 0 ? (present / total * 100).toInt() : 0;
    return LayoutBuilder(builder: (ctx, constraints) {
      if (constraints.maxWidth >= AppBreakpoints.phone) {
        // Tablet / desktop: single row of 4 KPI cards
        return Row(children: [
          Expanded(child: _statMini('Total Workers', '$total', sub: 'registered')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _statMini('Present', '$present', sub: '$pct% attendance', valueColor: AppColors.green)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _statMini('Late', '$late', sub: 'after check-in window', valueColor: AppColors.yellow)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _statMini('Absent', '$absent', sub: 'not on site', valueColor: AppColors.red)),
        ]);
      }
      // Phone: two compact rows
      return Column(children: [
        Row(children: [
          Expanded(child: _statMini('Total Workers', '$total', sub: 'registered')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _statMini('Present', '$present', sub: '$pct% attendance', valueColor: AppColors.green)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(child: _statMini('Late', '$late', sub: 'after check-in window', valueColor: AppColors.yellow)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _statMini('Absent', '$absent', sub: 'not on site', valueColor: AppColors.red)),
        ]),
      ]);
    });
  }

  Widget _statMini(String label, String value, {String? sub, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary)),
        if (sub != null) Text(sub, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _buildAttendanceRateCard(int present, int late, int absent) {
    final total = present + late + absent;
    final presentPct = total > 0 ? (present / total * 100).toInt() : 80;
    final latePct = total > 0 ? (late / total * 100).toInt() : 0;
    final absentPct = total > 0 ? (absent / total * 100).toInt() : 20;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Today's Attendance Rate — All Projects",
            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        StackedProgressBar(present: present > 0 ? present : 80, late: late, absent: absent > 0 ? absent : 20),
        const SizedBox(height: 10),
        Row(children: [
          _legend(AppColors.green, 'Present $presentPct%'),
          const SizedBox(width: 16),
          _legend(AppColors.yellow, 'Late $latePct%'),
          const SizedBox(width: 16),
          _legend(AppColors.red, 'Absent $absentPct%'),
        ]),
      ]),
    );
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ]);

  Widget _sectionLabel(String s) => Text(s,
      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary));

  Widget _buildFilterRow() {
    return Column(children: [
      // Search bar - full width
      SizedBox(
        height: 44,
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: AppStrings.t('att.searchWorker'),
            hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            filled: true, fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.accent, width: 1.4)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Filter row
      Row(children: [
        _filterDropdown(['All', 'Present', 'Late', 'Absent'], _statusFilter,
            (v) => setState(() => _statusFilter = v!)),
      ]),
    ]);
  }

  Widget _filterDropdown(List<String> items, String value, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ── Phone-friendly worker cards (replaces 7-column table) ──
  Widget _buildWorkerTable(List filtered) {
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(child: Text(AppStrings.t('att.noWorkers'), style: GoogleFonts.outfit(color: AppColors.textMuted))),
      );
    }
    return LayoutBuilder(builder: (ctx, constraints) {
      if (constraints.maxWidth < AppBreakpoints.phone) {
        return Column(
          children: filtered.map((w) => _WorkerAttCard(worker: w)).toList(),
        );
      }
      // Tablet / desktop: two-column grid
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.6,
        ),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _WorkerAttCard(worker: filtered[i], inGrid: true),
      );
    });
  }
}

class _WorkerAttCard extends StatelessWidget {
  final Map worker;
  final bool inGrid;
  const _WorkerAttCard({required this.worker, this.inGrid = false});

  String _fmtTime(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final status = worker['status'] as String? ?? 'absent';
    final name = worker['name'] as String? ?? '?';
    final trade = worker['trade'] as String? ?? 'Worker';
    final project = worker['project']?['project_name'] as String? ?? '—';
    final checkIn = _fmtTime(worker['check_in_time'] as String?);
    final checkOut = _fmtTime(worker['check_out_time'] as String?);
    final hours = worker['hours_today'];

    return Container(
      margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: avatar + name + status pill
        Row(children: [
          initialsAvatar(name, radius: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              Text(trade,
                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ),
          statusPill(status),
        ]),
        const SizedBox(height: 8),
        // Row 2: project
        Row(children: [
          Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Expanded(child: Text(project,
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        // Row 3: check-in / out / hours
        Row(children: [
          _timeChip(Icons.login_rounded, 'In', checkIn, AppColors.green),
          const SizedBox(width: 8),
          _timeChip(Icons.logout_rounded, 'Out', checkOut, AppColors.blue),
          const Spacer(),
          if (hours != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${hours}h',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accent)),
            ),
          const SizedBox(width: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.gps_fixed_rounded, size: 11, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('GPS', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
          ]),
        ]),
      ]),
    );
  }

  Widget _timeChip(IconData icon, String label, String time, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text('$label $time',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600,
              color: time == '—' ? AppColors.textMuted : color)),
    ]);
  }
}

class _ProjectGeofenceCard extends StatelessWidget {
  final Map project;
  const _ProjectGeofenceCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final name = project['project_name'] as String? ?? '—';
    final location = project['location_address'] as String? ?? '—';
    final radius = (project['fence_radius'] as num? ?? 5000).toInt();
    final workerCount = project['worker_count'] ?? project['tracked_workers'] ?? 0;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.gps_fixed_rounded, size: 13, color: AppColors.green),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(8)),
            child: Text(AppStrings.t('att.active'), style: GoogleFonts.outfit(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(_shortLoc(location), style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text('$workerCount workers tracked', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
        Text('Radius: ${radius}m', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
      ]),
    );
  }

  String _shortLoc(String loc) {
    final parts = loc.split(',');
    return parts.length >= 2 ? '${parts[parts.length - 2].trim()}, ${parts.last.trim()}' : loc;
  }
}
