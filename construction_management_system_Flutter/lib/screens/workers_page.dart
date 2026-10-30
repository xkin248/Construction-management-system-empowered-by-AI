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
import '../widgets/app_scrollbar.dart';
import '../widgets/worker_list_card.dart';
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

  /// Drives the always-visible scrollbar of the worker list.
  final ScrollController _scrollCtrl = ScrollController();

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
                        child: AppScrollbar(
                          controller: _scrollCtrl,
                          child: LayoutBuilder(builder: (ctx, constraints) {
                            // Filter once per build, then let the lazy list
                            // drive which cards are actually constructed.
                            final rows = _filtered;
                            if (constraints.maxWidth < AppBreakpoints.phone) {
                              return ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: rows.length,
                                addAutomaticKeepAlives: false,
                                itemBuilder: (ctx, i) => _buildCard(rows[i]),
                              );
                            }
                            // Tablet / desktop: two-column grid
                            return GridView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: AppSpacing.sm,
                                crossAxisSpacing: AppSpacing.sm,
                                mainAxisExtent: 152,
                              ),
                              itemCount: rows.length,
                              addAutomaticKeepAlives: false,
                              itemBuilder: (ctx, i) => _buildCard(rows[i], inGrid: true),
                            );
                          }),
                        ),
                      ),
              ),     // Expanded
            ]),      // Column
          ),
        ),
      ),
    );         // Scaffold
  }

  /// One lazy list item. The card itself is a standalone widget so scrolling
  /// never rebuilds this page's whole builder closure.
  Widget _buildCard(Map w, {bool inGrid = false}) {
    final wid = w['worker_id'] ?? w['id'];
    return WorkerListCard(
      key: ValueKey('worker-${wid ?? w['name']}'),
      worker: w,
      inGrid: inGrid,
      onTap: wid is int
          ? () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => WorkerDetailPage(workerId: wid, initial: w)))
          : null,
    );
  }
}

