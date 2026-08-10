import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

const _weathers = ['Sunny', 'Cloudy', 'Rain', 'Thunderstorm'];

class DailyReportPage extends StatefulWidget {
  const DailyReportPage({super.key});
  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  bool ld = true;
  List projects = [];
  List reports = [];
  int? pid;
  final wp = TextEditingController(), mat = TextEditingController(), iss = TextEditingController(), manpower = TextEditingController();
  String weather = 'Sunny';
  DateTime d = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    wp.dispose(); mat.dispose(); iss.dispose(); manpower.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
      if (projects.isNotEmpty) {
        pid ??= projects.first['project_id'];
        reports = await ApiService().getReports(pid!);
      }
    } catch (e) {
      toast('Failed to load reports: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _submit() async {
    if (pid == null) { toast('Please select a project'); return; }
    if (wp.text.trim().isEmpty) { toast('Please describe today\'s progress'); return; }
    try {
      await ApiService().submitReport({
        'project_id': pid, 'report_date': DateFormat('yyyy-MM-dd').format(d),
        'weather': weather, 'work_progress': wp.text, 'materials_used': mat.text,
        'issues_encountered': iss.text, 'manpower_count': int.tryParse(manpower.text) ?? 0, 'submitted_by': 1,
      });
      wp.clear(); mat.clear(); iss.clear(); manpower.clear();
      toast('✅ Daily report submitted');
      _load();
    } on DioException catch (e) {
      toast(e.message ?? 'Submission failed');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Submit Daily Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 14),
            if (projects.length > 1) ...[
              DropdownButtonFormField<int>(
              initialValue: pid,
                decoration: const InputDecoration(labelText: 'Project'),
                items: projects.map<DropdownMenuItem<int>>((p) => DropdownMenuItem(value: p['project_id'], child: Text(p['project_name']))).toList(),
                onChanged: (v) async { setState(() => pid = v); reports = await ApiService().getReports(v!); setState(() {}); },
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: weather,
              decoration: const InputDecoration(labelText: 'Weather'),
              items: _weathers.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
              onChanged: (v) => setState(() => weather = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: manpower, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Workers Present', hintText: 'e.g. 45')),
            const SizedBox(height: 12),
            TextField(controller: wp, maxLines: 3, decoration: const InputDecoration(labelText: "Today's Progress *", hintText: "Describe today's progress...")),
            const SizedBox(height: 12),
            TextField(controller: mat, maxLines: 2, decoration: const InputDecoration(labelText: 'Materials Used')),
            const SizedBox(height: 12),
            TextField(controller: iss, maxLines: 2, decoration: const InputDecoration(labelText: 'Safety Notes / Issues Encountered')),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Submit Report')),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Recent Reports', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        if (reports.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No reports submitted yet', style: TextStyle(color: AppColors.textMuted))))
        else
          ...reports.map((r) => sectionCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.description_outlined, color: AppColors.accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['report_date']} · ${r['weather'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(r['work_progress'] ?? 'No content', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ),
                  Text('${r['manpower_count'] ?? 0}\nworkers', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ]),
              )),
      ]),
    );
  }
}
