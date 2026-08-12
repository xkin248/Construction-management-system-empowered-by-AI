import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});
  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  bool ld = true;
  List workers = [];
  List projects = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final results = await Future.wait([ApiService().getWorkers(), ApiService().getProjects()]);
      workers = results[0];
      projects = results[1];
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
    int? pid = projects.isNotEmpty ? projects.first['project_id'] : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
          decoration: const BoxDecoration(
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
              Text('Add Worker', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Ali Hassan')),
              const SizedBox(height: 12),
              TextField(controller: role, decoration: const InputDecoration(labelText: 'Trade / Role', hintText: 'e.g. Electrician')),
              const SizedBox(height: 12),
              if (projects.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: pid,
                  decoration: const InputDecoration(labelText: 'Assigned Project'),
                  items: projects.map<DropdownMenuItem<int>>((p) =>
                      DropdownMenuItem(value: p['project_id'], child: Text(p['project_name']))).toList(),
                  onChanged: (v) => setD(() => pid = v),
                ),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', hintText: '+60 12-345 6789')),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (for login)', hintText: 'worker@example.com')),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', hintText: 'Min 8 chars')),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) { toast("Enter the worker's name"); return; }
                  try {
                    if (email.text.trim().isNotEmpty && password.text.isNotEmpty) {
                      // Register as authenticated worker
                      await ApiService().registerWorker(
                        name: name.text.trim(),
                        email: email.text.trim().toLowerCase(),
                        password: password.text,
                        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                        trade: role.text.trim().isEmpty ? null : role.text.trim(),
                        projectId: pid,
                      );
                    } else {
                      await ApiService().createWorker({
                        'name': name.text.trim(), 'trade': role.text.trim(),
                        'project_id': pid, 'phone': phone.text.trim(),
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    toast('Worker added!');
                    _load();
                  } on DioException catch (e) {
                    toast(e.message ?? 'Failed to add worker');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Add Worker', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
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
          label: const Text('Add Worker')),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search workers by name or trade...',
              hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
              filled: true, fillColor: AppColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            ),
          ),
        ),
        Expanded(
          child: ld
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(child: Text('No workers found', style: GoogleFonts.outfit(color: AppColors.textMuted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final w = _filtered[i];
                      return sectionCard(
                        margin: const EdgeInsets.only(bottom: 10),
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
                                  const Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
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
                    },
                  ),
                ),
        ),     // Expanded
      ]),      // Column
    );         // Scaffold
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
