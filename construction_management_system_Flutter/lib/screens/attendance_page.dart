
import '../widgets/app_page_intro.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/app_button.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/charts.dart';
import '../widgets/failure_state.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/supervisor/attendance_log_card.dart';

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

// ---------------------------------------------------------------------------
// Team attendance monitor (supervisor)
// ---------------------------------------------------------------------------
class _TeamAttendanceTab extends StatefulWidget {
  const _TeamAttendanceTab();

  @override
  State<_TeamAttendanceTab> createState() => _TeamAttendanceTabState();
}

class _TeamAttendanceTabState extends State<_TeamAttendanceTab> {
  /// Drives the always-available scrollbar of the attendance page.
  final ScrollController _scrollCtrl = ScrollController();

  bool ld = true;
  Object? _loadError;
  Map summary = {};
  List projects = [];
  String _searchQuery = '';
  String _statusFilter = 'All';

  // --------------------- Range switch: Today / Week / Month -------------------
  /// Which attendance window is on screen.
  ///
  /// `/attendance/today` returns one row per worker (times, project, GPS
  /// evidence, selfie); `/attendance/weekly-stats` returns Mon-Sun daily
  /// counts; no endpoint aggregates a whole month yet, so "This Month" states
  /// that gap instead of inventing a total.
  String _period = 'today'; // today | week | month
  List<Map> _weekDays = [];
  bool _weekLoading = false;
  Object? _weekError;

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _dayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

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
    _scrollCtrl.dispose();
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  // -------------------------------- Data ------------------------------------
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => ld = true);
    try {
      final results = await Future.wait([
        ApiService().attendanceToday(),
        ProjectCache.get(ApiService()),
      ]);
      summary = results[0] as Map;
      projects = results[1] as List;
      _loadError = null;
    } catch (e) {
      _loadError = e;
      toast(AppSettings.t(
        'Attendance could not be loaded. Check the connection and try again.',
        '考勤数据加载失败，请检查网络后重试。',
        'Kehadiran gagal dimuatkan. Sila cuba lagi.',
      ));
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _loadWeek() async {
    setState(() {
      _weekLoading = true;
      _weekError = null;
    });
    try {
      final weekly = await ApiService().getWeeklyAttendanceStats();
      _weekDays = List<Map>.from(weekly['days'] ?? []);
    } catch (e) {
      _weekError = e;
    } finally {
      if (mounted) setState(() => _weekLoading = false);
    }
  }

  void _setPeriod(String p) {
    if (_period == p) return;
    setState(() => _period = p);
    if (p == 'week' && _weekDays.isEmpty && !_weekLoading) _loadWeek();
  }

  Future<void> _refreshCurrent() async {
    if (_period == 'week') {
      await _loadWeek();
    } else if (_period == 'today') {
      await _load(silent: true);
    }
  }

  // ------------------------------- Helpers ----------------------------------
  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_monthNames[d.month - 1]} ${d.year}';

  /// Geofence radius (metres) of the worker's project, used by the attendance
  /// card to judge whether the check-in GPS point was inside the fence.
  double? _fenceRadiusFor(Map worker) {
    final proj = worker['project'];
    if (proj is Map) {
      final r = _asDouble(proj['fence_radius']);
      if (r != null) return r;
    }
    final direct = _asDouble(worker['fence_radius']);
    if (direct != null) return direct;
    final pid = worker['project_id'] ?? (proj is Map ? proj['project_id'] : null);
    final pname = proj is Map ? proj['project_name'] : null;
    for (final p in projects) {
      if (p is! Map) continue;
      final matches = (pid != null && (p['project_id'] == pid || p['id'] == pid)) ||
          (pname != null && p['project_name'] == pname);
      if (!matches) continue;
      final r = _asDouble(p['fence_radius']);
      if (r != null) return r;
    }
    return null;
  }

  List<Map> _filteredRows(List rows) {
    final q = _searchQuery.trim().toLowerCase();
    return rows.where((dynamic raw) {
      if (raw is! Map) return false;
      final name = '${raw['name'] ?? ''}'.toLowerCase();
      final projectName = raw['project'] is Map
          ? '${raw['project']['project_name'] ?? ''}'.toLowerCase()
          : '${raw['project_name'] ?? ''}'.toLowerCase();
      final status = '${raw['status'] ?? raw['today_status'] ?? 'absent'}'.toLowerCase();
      final matchSearch = q.isEmpty || name.contains(q) || projectName.contains(q);
      final matchStatus = _statusFilter == 'All' || status == _statusFilter.toLowerCase();
      return matchSearch && matchStatus;
    }).map<Map>((dynamic raw) => raw as Map).toList();
  }

  // -------------------------------- Build -----------------------------------
  @override
  Widget build(BuildContext c) {
    if (ld) {
      return const SkeletonList(rows: 5, showHeader: true, headerStatCount: 4);
    }
    if (_loadError != null && summary.isEmpty) {
      return FailureState(error: _loadError, onRetry: _load);
    }

    final rows = (summary['rows'] as List?) ?? [];
    final filtered = _filteredRows(rows);

    return RefreshIndicator(
      onRefresh: _refreshCurrent,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: AppScrollbar(
              controller: _scrollCtrl,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList.list(
                      children: [
          AppPageIntro(
            icon: Icons.fact_check_rounded,
            enTitle: 'ATTENDANCE',
            msTitle: 'KEHADIRAN',
            zhTitle: '考勤记录',
            enSubtitle: 'Check site attendance by day, week or month',
            msSubtitle: 'Semak kehadiran harian, mingguan atau bulanan',
            zhSubtitle: '按日、周或月查看考勤',
            worker: false,
          ),
          const SizedBox(height: 14),
          _periodSwitch(),
                        const SizedBox(height: 12),
                        _rangeCaption(),
                        const SizedBox(height: 16),
                        if (_period == 'today') ..._todaySections(filtered)
                        else if (_period == 'week') ..._weekSections()
                        else ..._monthSections(),
                      ],
                    ),
                  ),
                  if (_period == 'today') _workerSliver(filtered),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------- Range switch UI ------------------------------
  /// Three equal-width segments so nothing scrolls sideways on a phone.
  Widget _periodSwitch() {
    final items = <List<String>>[
      ['today', AppSettings.t('Today', '今天', 'Hari ini')],
      ['week', AppSettings.t('This Week', '本周', 'Minggu ini')],
      ['month', AppSettings.t('This Month', '本月', 'Bulan ini')],
    ];
    final icons = <String, IconData>{
      'today': Icons.today_rounded,
      'week': Icons.date_range_rounded,
      'month': Icons.calendar_month_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _setPeriod(it[0]),
                  borderRadius: AppRadius.rSm,
                  child: AnimatedContainer(
                    duration: AppDuration.fast,
                    curve: AppDuration.ease,
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _period == it[0] ? AppColors.navy : Colors.transparent,
                      borderRadius: AppRadius.rSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icons[it[0]],
                          size: 14,
                          color: _period == it[0] ? Colors.white : AppColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            it[1],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _period == it[0] ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One line that tells the supervisor exactly which slice of data is shown.
  Widget _rangeCaption() {
    final now = DateTime.now();
    final String window;
    if (_period == 'today') {
      window = AppSettings.t('Today', '今天', 'Hari ini');
    } else if (_period == 'week') {
      window = AppSettings.t('This week (Mon-Sun)', '本周（周一至周日）', 'Minggu ini (Isnin-Ahad)');
    } else {
      window = AppSettings.t('This month', '本月', 'Bulan ini');
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            '$window · ${AppSettings.t('All projects', '全部项目', 'Semua projek')} · ${_fmtDate(now)}',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        semanticIconRefresh(),
      ],
    );
  }

  Widget semanticIconRefresh() {
    final busy = _period == 'week' ? _weekLoading : false;
    return IconButton(
      onPressed: busy ? null : _refreshCurrent,
      tooltip: AppSettings.t('Refresh', '刷新', 'Muat semula'),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
      color: AppColors.textSecondary,
    );
  }

  // ------------------------------ Today view --------------------------------
  List<Widget> _todaySections(List<Map> filtered) {
    final present = _asInt(summary['present']);
    final late = _asInt(summary['late']);
    final absent = _asInt(summary['absent']);
    final total = _asInt(summary['total']) == 0
        ? ((summary['rows'] as List?) ?? []).length
        : _asInt(summary['total']);

    return [
      _kpiStrip([
        _Kpi(AppSettings.t('Total', '总人数', 'Jumlah'), '$total', AppColors.textPrimary,
            Icons.groups_rounded),
        _Kpi(AppSettings.t('Present', '已出勤', 'Hadir'), '$present', AppColors.green,
            Icons.check_circle_rounded),
        _Kpi(AppSettings.t('Late', '迟到', 'Lewat'), '$late', AppColors.yellow,
            Icons.schedule_rounded),
        _Kpi(AppSettings.t('Absent', '缺勤', 'Tidak hadir'), '$absent', AppColors.red,
            Icons.person_off_rounded),
      ]),
      const SizedBox(height: 12),
      _toolbar(),
      const SizedBox(height: 14),
      _sectionHeader(
        AppSettings.t('Worker logs', '工人打卡明细', 'Log pekerja'),
        AppSettings.t('${filtered.length} of ${(summary['rows'] as List?)?.length ?? 0}',
            '共 ${filtered.length} / ${(summary['rows'] as List?)?.length ?? 0} 人',
            '${filtered.length} daripada ${(summary['rows'] as List?)?.length ?? 0}'),
      ),
      const SizedBox(height: 10),
    ];
  }

  /// Search + status filter, stacked so nothing needs a sideways scroll.
  Widget _toolbar() {
    const statuses = ['All', 'Present', 'Late', 'Absent'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: AppSettings.t('Search worker or project', '搜索工人或项目', 'Cari pekerja atau projek'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: AppRadius.rMd,
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.rMd,
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.rMd,
              borderSide: BorderSide(color: AppColors.accent, width: 1.4),
            ),
          ),
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in statuses)
              _filterChip(
                s,
                s == 'All'
                    ? AppSettings.t('All', '全部', 'Semua')
                    : s == 'Present'
                        ? AppSettings.t('Present', '已出勤', 'Hadir')
                        : s == 'Late'
                            ? AppSettings.t('Late', '迟到', 'Lewat')
                            : AppSettings.t('Absent', '缺勤', 'Tidak hadir'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    final active = _statusFilter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.rPill,
        onTap: () => setState(() => _statusFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.accentLight : AppColors.bgCard,
            borderRadius: AppRadius.rPill,
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.accentText : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// Worker cards. Phone = one column (no horizontal scrolling, the old wide
  /// table forced a sideways swipe); >= 700px = two columns.
  Widget _workerSliver(List<Map> filtered) {
    final rowsAll = (summary['rows'] as List?) ?? [];
    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: sectionCard(
            child: GuidedEmptyState(
              compact: true,
              icon: rowsAll.isEmpty ? Icons.event_busy_rounded : Icons.search_off_rounded,
              title: rowsAll.isEmpty
                  ? AppSettings.t('No attendance today', '今天还没有打卡记录', 'Tiada kehadiran hari ini')
                  : AppSettings.t('No worker matches', '没有匹配的工人', 'Tiada pekerja sepadan'),
              description: rowsAll.isEmpty
                  ? AppSettings.t(
                      'Nobody has clocked in yet. Pull down or tap refresh to check again.',
                      '还没有人打卡。下拉或点击刷新可重新获取。',
                      'Belum ada yang daftar masuk. Tarik ke bawah atau tekan muat semula.',
                    )
                  : AppSettings.t(
                      'Clear the search or pick another status filter.',
                      '清除搜索词或切换状态筛选。',
                      'Kosongkan carian atau tukar penapis status.',
                    ),
              primaryLabel: rowsAll.isEmpty
                  ? AppSettings.t('Refresh', '刷新', 'Muat semula')
                  : AppSettings.t('Reset filters', '重置筛选', 'Set semula penapis'),
              primaryIcon: rowsAll.isEmpty ? Icons.refresh_rounded : Icons.filter_alt_off_rounded,
              onPrimary: () {
                if (rowsAll.isEmpty) {
                  _refreshCurrent();
                } else {
                  setState(() {
                    _searchQuery = '';
                    _statusFilter = 'All';
                  });
                }
              },
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.crossAxisExtent >= 700;
          if (twoCol) {
            return SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 300,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => AttendanceLogCard(
                  row: filtered[i],
                  fenceRadiusM: _fenceRadiusFor(filtered[i]),
                  inGrid: true,
                ),
                childCount: filtered.length,
              ),
            );
          }
          return SliverList.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => AttendanceLogCard(
              row: filtered[i],
              fenceRadiusM: _fenceRadiusFor(filtered[i]),
              showProject: true,
            ),
          );
        },
      ),
    );
  }

  // ---------------------------- Shared blocks -------------------------------
  Widget _sectionHeader(String title, String? trailing) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
                fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          ),
      ],
    );
  }

  /// Compact KPI strip: four tiles shrink to a 2x2 block on narrow phones.
  Widget _kpiStrip(List<_Kpi> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth < 430 ? 2 : 4;
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += perRow) {
          final slice = items.sublist(i, (i + perRow).clamp(0, items.length));
          rows.add(Row(
            children: [
              for (var j = 0; j < perRow; j++) ...[
                Expanded(
                  child: j < slice.length ? _kpiTile(slice[j]) : const SizedBox(),
                ),
                if (j != perRow - 1) const SizedBox(width: 8),
              ],
            ],
          ));
          if (i + perRow < items.length) rows.add(const SizedBox(height: 8));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _kpiTile(_Kpi k) {
    return sectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(k.icon, size: 14, color: k.color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            k.value,
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w800, color: k.color),
          ),
        ],
      ),
    );
  }

  // ------------------------------- Week view --------------------------------
  List<Widget> _weekSections() {
    if (_weekLoading && _weekDays.isEmpty) {
      return [
        const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    if (_weekError != null && _weekDays.isEmpty) {
      return [
        sectionCard(
          child: FailureState(
            error: _weekError,
            compact: true,
            onRetry: _loadWeek,
            retryLabel: AppSettings.t('Retry', '重试', 'Cuba lagi'),
          ),
        ),
      ];
    }

    final days = _weekDays;
    final checkIns = days.fold<int>(0, (a, d) => a + _asInt(d['check_in_count']));
    final presentSum = days.fold<int>(0, (a, d) => a + _asInt(d['present_workers']));
    final avgPresent = days.isEmpty ? 0 : (presentSum / days.length).round();
    final todayRow = days.where((d) => d['is_today'] == true).toList();
    final todayPresent = todayRow.isEmpty ? 0 : _asInt(todayRow.first['present_workers']);

    return [
      _kpiStrip([
        _Kpi(AppSettings.t('Days', '统计天数', 'Hari'), '${days.length}', AppColors.textPrimary,
            Icons.date_range_rounded),
        _Kpi(AppSettings.t('Check-ins', '打卡次数', 'Daftar masuk'), '$checkIns', AppColors.blue,
            Icons.fingerprint_rounded),
        _Kpi(AppSettings.t('Avg present', '日均出勤', 'Purata hadir'), '$avgPresent',
            AppColors.green, Icons.trending_up_rounded),
        _Kpi(AppSettings.t('Today', '今日出勤', 'Hari ini'), '$todayPresent', AppColors.yellow,
            Icons.today_rounded),
      ]),
      const SizedBox(height: 12),
      sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              AppSettings.t('Check-ins this week', '本周打卡趋势', 'Daftar masuk minggu ini'),
              days.isEmpty ? null : AppSettings.t('Mon – Sun', '周一至周日', 'Isnin – Ahad'),
            ),
            const SizedBox(height: 14),
            if (days.isEmpty)
              GuidedEmptyState(
                compact: true,
                icon: Icons.bar_chart_rounded,
                title: AppSettings.t('No weekly data', '暂无本周数据', 'Tiada data mingguan'),
                description: AppSettings.t(
                  'The weekly endpoint returned no days yet.',
                  '周统计接口暂未返回数据。',
                  'Endpoint mingguan belum memulangkan hari.',
                ),
                primaryLabel: AppSettings.t('Refresh', '刷新', 'Muat semula'),
                primaryIcon: Icons.refresh_rounded,
                onPrimary: _loadWeek,
              )
            else
              LabeledBarChart(
                values: days
                    .map<double>((d) => _asInt(d['check_in_count']).toDouble())
                    .toList(),
                labels: days.map<String>((d) {
                  final wd = '${d['weekday'] ?? ''}';
                  return _shortWeekday(wd);
                }).toList(),
                height: 150,
                highlightColor: AppColors.accent,
              ),
            const SizedBox(height: 12),
            Text(
              AppSettings.t(
                'Source: /attendance/weekly-stats. The endpoint returns company-wide daily counts and no per-project split, so no project filter is applied here.',
                '数据来源：/attendance/weekly-stats。该接口仅返回公司级每日统计，没有项目维度拆分，因此此处不做项目筛选。',
                'Sumber: /attendance/weekly-stats. Endpoint ini hanya memulangkan kiraan harian seluruh syarikat tanpa pecahan projek.',
              ),
              style: GoogleFonts.inter(fontSize: 11.5, height: 1.45, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _sectionHeader(
        AppSettings.t('Daily breakdown', '每日明细', 'Pecahan harian'),
        '${days.length} ${AppSettings.t('days', '天', 'hari')}',
      ),
      const SizedBox(height: 10),
      if (days.isEmpty)
        sectionCard(
          child: Text(
            AppSettings.t('Nothing to break down yet.', '暂无可展开的每日明细。', 'Tiada pecahan untuk dipaparkan.'),
            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        )
      else
        sectionCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              for (var i = 0; i < days.length; i++) ...[
                _dayRow(days[i]),
                if (i != days.length - 1) Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        ),
    ];
  }

  String _shortWeekday(String raw) {
    final l = raw.trim().toLowerCase();
    for (final d in _dayNames) {
      if (l.startsWith(d.toLowerCase())) return d;
    }
    if (l.startsWith('mon')) return 'Mon';
    return raw.length > 3 ? raw.substring(0, 3) : raw;
  }

  Widget _dayRow(Map d) {
    final isToday = d['is_today'] == true;
    final present = _asInt(d['present_workers']);
    final checkIns = _asInt(d['check_in_count']);
    final dateRaw = '${d['date'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              _shortWeekday('${d['weekday'] ?? ''}'),
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isToday ? AppColors.accentText : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Text(
            AppSettings.t('$present present', '$present 人出勤', '$present hadir'),
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.blueLight,
              borderRadius: AppRadius.rSm,
            ),
            child: Text(
              '$checkIns',
              style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.blue),
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: AppRadius.rSm,
              ),
              child: Text(
                AppSettings.t('Today', '今天', 'Hari ini'),
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------- Month view -------------------------------
  /// No monthly aggregation endpoint exists (`/attendance/today` is a single
  /// day, `/attendance/weekly-stats` is Mon-Sun). Instead of inventing a month
  /// total this view explains the gap and offers the real 7-day window.
  List<Widget> _monthSections() {
    final now = DateTime.now();
    final monthLabel = '${_monthNames[now.month - 1]} ${now.year}';
    final checkIns = _weekDays.fold<int>(0, (a, d) => a + _asInt(d['check_in_count']));
    final presentSum = _weekDays.fold<int>(0, (a, d) => a + _asInt(d['present_workers']));
    final first = now.subtract(Duration(days: now.weekday - 1));
    final last = first.add(const Duration(days: 6));

    return [
      sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: AppRadius.rSm,
                  ),
                  child: Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.accentText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppSettings.t('Month totals are not available yet',
                        '月度汇总暂不可用', 'Jumlah bulanan belum tersedia'),
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              AppSettings.t(
                '$monthLabel cannot be aggregated: the backend only exposes a single-day summary (/attendance/today) and a Mon–Sun window (/attendance/weekly-stats). Showing a month figure here would mean fabricating data, so this tab reports the verified 7-day window instead.',
                '$monthLabel 暂无月度汇总：后端只提供单日汇总（/attendance/today）与周一至周日窗口（/attendance/weekly-stats）。此处若给出月度数字即为伪造，因此改为展示已核实的 7 天窗口数据。',
                '$monthLabel tidak dapat diagregat: backend hanya menyediakan ringkasan sehari (/attendance/today) dan tetingkap Isnin–Ahad (/attendance/weekly-stats).',
              ),
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: _weekDays.isEmpty
                  ? AppSettings.t('Load this week', '加载本周数据', 'Muat minggu ini')
                  : AppSettings.t('Open this week', '查看本周', 'Buka minggu ini'),
              icon: _weekDays.isEmpty ? Icons.download_rounded : Icons.arrow_forward_rounded,
              tone: AppButtonTone.secondary,
              height: 46,
              loading: _weekLoading,
              loadingLabel: AppSettings.t('Loading…', '加载中…', 'Memuatkan…'),
              onPressed: _weekLoading
                  ? null
                  : () async {
                      if (_weekDays.isEmpty) {
                        await _loadWeek();
                      }
                      if (mounted && _weekDays.isNotEmpty) _setPeriod('week');
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _sectionHeader(
        AppSettings.t('Verified 7-day window', '已核实的 7 天窗口', 'Tetingkap 7 hari disahkan'),
        '${_fmtDate(first)} – ${_fmtDate(last)}',
      ),
      const SizedBox(height: 10),
      if (_weekDays.isEmpty)
        sectionCard(
          child: GuidedEmptyState(
            compact: true,
            icon: Icons.calendar_month_rounded,
            title: AppSettings.t('No 7-day data loaded', '尚未加载 7 天数据', 'Data 7 hari belum dimuatkan'),
            description: AppSettings.t(
              'Tap the button above to load the current Mon–Sun attendance counts.',
              '点击上方按钮加载本周周一至周日的考勤统计。',
              'Tekan butang di atas untuk memuatkan kiraan Isnin–Ahad.',
            ),
            primaryLabel: AppSettings.t('Load now', '立即加载', 'Muat sekarang'),
            primaryIcon: Icons.refresh_rounded,
            onPrimary: _loadWeek,
          ),
        )
      else ...[
        _kpiStrip([
          _Kpi(AppSettings.t('Check-ins', '打卡次数', 'Daftar masuk'), '$checkIns',
              AppColors.blue, Icons.fingerprint_rounded),
          _Kpi(AppSettings.t('Present (sum)', '出勤人次', 'Jumlah hadir'), '$presentSum',
              AppColors.green, Icons.groups_rounded),
          _Kpi(AppSettings.t('Days', '天数', 'Hari'), '${_weekDays.length}',
              AppColors.textPrimary, Icons.date_range_rounded),
          _Kpi(
            AppSettings.t('Best day', '最高单日', 'Hari terbaik'),
            '${_weekDays.map<int>((d) => _asInt(d['check_in_count'])).fold<int>(0, (a, b) => a > b ? a : b)}',
            AppColors.yellow,
            Icons.emoji_events_rounded,
          ),
        ]),
        const SizedBox(height: 12),
        sectionCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              for (var i = 0; i < _weekDays.length; i++) ...[
                _dayRow(_weekDays[i]),
                if (i != _weekDays.length - 1) Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        ),
      ],
    ];
  }
}

/// Small value object for the KPI strip tiles.
class _Kpi {
  const _Kpi(this.label, this.value, this.color, this.icon);
  final String label;
  final String value;
  final Color color;
  final IconData icon;
}
