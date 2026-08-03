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
    final name = TextEditingController(), role = TextEditingController(), phone = TextEditingController();
    int? pid = projects.isNotEmpty ? projects.first['project_id'] : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text('Add Worker', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Ali Hassan')),
              const SizedBox(height: 12),
              TextField(controller: role, decoration: const InputDecoration(labelText: 'Trade / Role', hintText: 'e.g. Electrician')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: pid,
                decoration: const InputDecoration(labelText: 'Assigned Project'),
                items: projects.map<DropdownMenuItem<int>>((p) =>
                    DropdownMenuItem(value: p['project_id'], child: Text(p['project_name']))).toList(),
                onChanged: (v) => setD(() => pid = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', hintText: '+60 12-345 6789')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) { toast("Enter the worker's name"); return; }
                try {
                  await ApiService().createWorker({
                    'name': name.text.trim(), 'trade': role.text.trim(),
                    'project_id': pid, 'phone': phone.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('✅ Worker added');
                  _load();
                } on DioException catch (e) {
                  toast(e.message ?? 'Failed to add worker');
                }
              },
              child: const Text('Add Worker'),
            ),
          ],
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
                                  style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12)),
                              if (w['project'] != null) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
                                  const SizedBox(width: 3),
                                  Expanded(child: Text(w['project']['project_name'] ?? '',
                                      style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11.5),
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
                                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
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
