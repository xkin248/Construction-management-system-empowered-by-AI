import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool ld = true;
  List projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
    } catch (e) {
      toast('Failed to load projects: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  void _openNewProject() {
    final name = TextEditingController(), loc = TextEditingController(), budget = TextEditingController();
    DateTime? start, due;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pick(bool isStart) async {
          final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
          if (d != null) setD(() => isStart ? start = d : due = d);
        }

        return AlertDialog(
          title: const Text('New Project'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Project Name', hintText: 'e.g. Penang Tower C')),
              const SizedBox(height: 12),
              TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location', hintText: 'Address')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pick(true),
                    child: Text(start == null ? 'Start Date' : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pick(false),
                    child: Text(due == null ? 'Due Date' : '${due!.year}-${due!.month.toString().padLeft(2, '0')}-${due!.day.toString().padLeft(2, '0')}'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Budget (RM)', hintText: 'e.g. 4200000')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || loc.text.trim().isEmpty) {
                  toast('Please fill in the project name and location');
                  return;
                }
                try {
                  await ApiService().createProject({
                    'project_name': name.text.trim(), 'location_address': loc.text.trim(),
                    'start_date': start?.toIso8601String().split('T').first,
                    'end_date': due?.toIso8601String().split('T').first,
                    'status': 'planning', 'progress': 0.0,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('✅ Project created');
                  _load();
                } on DioException catch (e) {
                  toast(e.message ?? 'Failed to create project');
                }
              },
              child: const Text('Create Project'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _openNewProject, icon: const Icon(Icons.add), label: const Text('New Project')),
      body: ld
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: projects.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No projects yet', style: TextStyle(color: AppColors.textMuted))))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: projects.length,
                      itemBuilder: (ctx, i) {
                        final p = projects[i];
                        final progress = (p['progress'] as num? ?? 0).toDouble();
                        final workerCount = p['worker_count'] ?? p['tracked_workers'] ?? 0;
                        return sectionCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ProjectDetailPage(projectId: p['project_id']))),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Text(p['project_name'] ?? '-',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  statusPill(p['status'] ?? 'planning'),
                                ]),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
                                  const SizedBox(width: 3),
                                  Expanded(child: Text(p['location_address'] ?? '-',
                                      style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12),
                                      overflow: TextOverflow.ellipsis)),
                                ]),
                                const SizedBox(height: 12),
                                // Geofence + worker count
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(8)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.gps_fixed_rounded, size: 11, color: AppColors.green),
                                      const SizedBox(width: 4),
                                      Text('Geofence Active', style: GoogleFonts.outfit(fontSize: 10, color: AppColors.green, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                  if (workerCount > 0) ...[
                                    const SizedBox(width: 10),
                                    Text('$workerCount workers tracked',
                                        style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.w600)),
                                  ],
                                  const Spacer(),
                                  Text('Radius: ${(p['fence_radius'] as num? ?? 200).toInt()}m',
                                      style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted)),
                                ]),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: progress / 100,
                                    minHeight: 7, backgroundColor: AppColors.border,
                                    valueColor: const AlwaysStoppedAnimation(AppColors.green),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text('${progress.toStringAsFixed(0)}% complete',
                                      style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted)),
                                  if (p['end_date'] != null)
                                    Text('Due ${p['end_date']}',
                                        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted)),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}


class ProjectDetailPage extends StatefulWidget {
  final int projectId;
  const ProjectDetailPage({super.key, required this.projectId});
  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool ld = true;
  Map? project;
  List tasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final all = await ApiService().getProjects();
      project = all.firstWhere((p) => p['project_id'] == widget.projectId, orElse: () => null);
      tasks = await ApiService().getTasks(widget.projectId);
    } catch (e) {
      toast('Failed to load project: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (project == null) return const Scaffold(body: Center(child: Text('Project not found')));
    final p = project!;
    final completed = tasks.where((t) => t['status'] == 'completed').length;
    return Scaffold(
      appBar: AppBar(title: Text(p['project_name'] ?? 'Project')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.sidebarBg, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(p['project_name'] ?? '-', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
              statusPill(p['status'] ?? 'planning'),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.place_outlined, size: 13, color: AppColors.textSidebarMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(p['location_address'] ?? '-', style: const TextStyle(color: AppColors.textSidebarMuted, fontSize: 12.5))),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Overall Completion', style: TextStyle(color: AppColors.textSidebarMuted, fontSize: 11.5)),
              Text('${p['progress']?.toStringAsFixed(0) ?? 0}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ((p['progress'] ?? 0) as num) / 100, minHeight: 8, backgroundColor: AppColors.sidebarHover,
                  valueColor: const AlwaysStoppedAnimation(AppColors.green)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: statCard(label: 'Start', value: p['start_date'] ?? '—')),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Due', value: p['end_date'] ?? '—')),
        ]),
        const SizedBox(height: 16),
        const Text('Task Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: statCard(label: 'Total', value: '${tasks.length}')),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Completed', value: '$completed', iconColor: AppColors.green)),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Remaining', value: '${tasks.length - completed}', iconColor: AppColors.accent)),
        ]),
        const SizedBox(height: 16),
        sectionCard(
          child: Row(children: [
            const Icon(Icons.gps_fixed_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('Geofence Active · Radius ${p['fence_radius']?.toStringAsFixed(0) ?? 500}m', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            statusPill('active'),
          ]),
        ),
      ]),
    );
  }
}
