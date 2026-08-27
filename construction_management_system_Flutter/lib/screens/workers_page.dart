import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/add_worker_sheet.dart';

class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});
  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  bool ld = true;
  List workers = [];
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
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddWorker,
          icon: const Icon(Icons.add),
          label: Text(AppStrings.t('workers.addWorker'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: AppStrings.t('workers.searchHint'),
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
              Expanded(
                child: ld
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text(AppStrings.t('workers.noWorkersFound'), style: GoogleFonts.outfit(color: AppColors.textMuted)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: LayoutBuilder(builder: (ctx, constraints) {
                          if (constraints.maxWidth < AppBreakpoints.phone) {
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) => _workerCard(_filtered[i]),
                            );
                          }
                          // Tablet / desktop: two-column grid
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                              childAspectRatio: 1.6,
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
    return sectionCard(
      margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        initialsAvatar(w['name'] ?? '?', radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(w['name'] ?? '-',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14.5),
                  overflow: TextOverflow.ellipsis)),
              statusPill(w['today_status'] ?? 'absent'),
            ]),
            const SizedBox(height: 2),
            Text(w['trade'] ?? 'General Worker',
                style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14)),
            if (w['project'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Expanded(child: Text(w['project']['project_name'] ?? '',
                    style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ],
            if (w['check_in_time'] != null || w['hours_today'] != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (w['check_in_time'] != null) 'In ${_fmtTime(w['check_in_time'])}',
                  if (w['check_out_time'] != null) 'Out ${_fmtTime(w['check_out_time'])}',
                  if (w['hours_today'] != null) '${w['hours_today']}h',
                ].join(' · '),
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ]),
        ),
      ]),
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
