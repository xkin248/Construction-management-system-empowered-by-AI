import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/add_worker_sheet.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import 'worker_detail_page.dart';

class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});
  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  bool ld = true;
  List workers = [];
  Object? _loadError;
  String _searchQuery = '';

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
      workers = await ApiService().getWorkers();
    } catch (e) {
      _loadError = e;
      toast('Failed to load workers: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  List get _filtered => workers.where((w) {
        final name = (w['name'] as String? ?? '').toLowerCase();
        final trade = (w['trade'] as String? ?? '').toLowerCase();
        return _searchQuery.isEmpty ||
            name.contains(_searchQuery.toLowerCase()) ||
            trade.contains(_searchQuery.toLowerCase());
      }).toList();

  void _openAddWorker() {
    showAddWorkerSheet(context, onAdded: _load);
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      floatingActionButton: FloatingActionButton.extended(
          heroTag: const ValueKey('fab_workers'),
          onPressed: _openAddWorker,
          backgroundColor: AppColors.accent,
          icon: const Icon(Icons.add),
          label: Text(AppStrings.t('workers.addWorker'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              // Summary strip — derived from the already-loaded list (no API change)
              if (!ld && workers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: statCard(
                        label: AppStrings.t('workers.title'),
                        value: '${workers.length}',
                        icon: Icons.groups_2_outlined,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: statCard(
                        label: AppStrings.t('dash.present'),
                        value:
                            '${workers.where((w) => w['today_status'] == 'present').length}',
                        icon: Icons.how_to_reg_outlined,
                        iconColor: AppColors.green,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: statCard(
                        label: AppStrings.t('dash.absent'),
                        value:
                            '${workers.where((w) => w['today_status'] == 'absent').length}',
                        icon: Icons.person_off_outlined,
                        iconColor: AppColors.red,
                      ),
                    ),
                  ]),
                ),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: AppStrings.t('workers.searchHint'),
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
                      filled: true, fillColor: AppColors.bgCard,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.accent, width: 1.4)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ld
                ? const SkeletonList(rows: 6)
                : (_loadError != null && workers.isEmpty)
                    ? FailureState(error: _loadError, onRetry: _load)
                    : _filtered.isEmpty
                    ? (_searchQuery.isEmpty
                        ? GuidedEmptyState(
                            icon: Icons.group_off_rounded,
                            title: AppStrings.t('empty.workers.title'),
                            description: AppStrings.t('empty.workers.desc'),
                            primaryLabel: AppStrings.t('empty.workers.action'),
                            primaryIcon: Icons.person_add_alt_1_rounded,
                            onPrimary: _openAddWorker,
                          )
                        : FilteredEmptyState(
                            title: AppStrings.t('workers.noWorkersFound'),
                            description: AppStrings.t('empty.workers.noMatchDesc'),
                            clearLabel: AppStrings.t('empty.clearSearch'),
                            onClear: () => setState(() => _searchQuery = ''),
                          ))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: LayoutBuilder(builder: (ctx, constraints) {
                          if (constraints.maxWidth < AppBreakpoints.phone) {
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) => _workerCard(_filtered[i]),
                            );
                          }
                          // Tablet / desktop: two-column grid
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                              mainAxisExtent: 152,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) => _workerCard(_filtered[i], inGrid: true),
                          );
                        }),
                      ),
              ),     // Expanded
            ]),      // Column
          ),
        ),
      ),
    );         // Scaffold
  }

  Widget _workerCard(Map w, {bool inGrid = false}) {
    // Tapping a card opens the read-only worker profile (P1: cards previously
    // had no entry point at all).
    final wid = w['worker_id'] ?? w['id'];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: wid is int
          ? () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => WorkerDetailPage(workerId: wid, initial: w)))
          : null,
      child: sectionCard(
      margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        initialsAvatar(w['name'] ?? '?', radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(w['name'] ?? '-',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14.5),
                  overflow: TextOverflow.ellipsis)),
              statusPill(w['today_status'] ?? 'absent'),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.handyman_outlined, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(w['trade'] ?? 'General Worker',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis)),
            ]),
            if (w['project'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(child: Text(w['project']['project_name'] ?? '',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ],
            if (w['check_in_time'] != null || w['hours_today'] != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text(
                  [
                    if (w['check_in_time'] != null) 'In ${_fmtTime(w['check_in_time'])}',
                    if (w['check_out_time'] != null) 'Out ${_fmtTime(w['check_out_time'])}',
                    if (w['hours_today'] != null) '${w['hours_today']}h',
                  ].join(' · '),
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ],
          ]),
        ),
      ]),
      ),
    );
  }

  String _fmtTime(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

