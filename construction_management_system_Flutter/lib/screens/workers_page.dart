import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../l10n/app_strings.dart';

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
    final name = TextEditingController();
    final role = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(AppStrings.t('workers.addWorker'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(controller: name, decoration: InputDecoration(labelText: AppStrings.t('workers.fullName'), hintText: AppStrings.t('workers.fullNameHint'))),
              const SizedBox(height: 12),
              TextField(controller: role, decoration: InputDecoration(labelText: AppStrings.t('workers.tradeRole'), hintText: AppStrings.t('workers.tradeRoleHint'))),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.phone'), hintText: AppStrings.t('workers.phoneHint'))),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.emailForLogin'), hintText: AppStrings.t('workers.emailHint'))),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: true,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.password'), hintText: AppStrings.t('workers.passwordHint'))),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) { toast(AppStrings.t('workers.nameRequired')); return; }
                  try {
                    if (email.text.trim().isNotEmpty && password.text.isNotEmpty) {
                      // Register as authenticated worker (project auto-assigned by backend)
                      await ApiService().registerWorker(
                        name: name.text.trim(),
                        email: email.text.trim().toLowerCase(),
                        password: password.text,
                        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                        trade: role.text.trim().isEmpty ? null : role.text.trim(),
                      );
                    } else {
                      await ApiService().createWorker({
                        'name': name.text.trim(), 'trade': role.text.trim(),
                        'phone': phone.text.trim(),
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    toast(AppStrings.t('workers.added'));
                    _load();
                  } on DioException catch (e) {
                    toast(e.message ?? AppStrings.t('common.failed'));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppStrings.t('workers.addWorker'), style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        );
      }),
    );
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
