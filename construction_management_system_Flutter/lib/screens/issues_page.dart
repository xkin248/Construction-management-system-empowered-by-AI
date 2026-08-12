import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

const _severities = ['low', 'medium', 'high'];
const _categories = ['safety', 'delay', 'equipment', 'quality', 'other'];

class IssuesPage extends StatefulWidget {
  const IssuesPage({super.key});
  @override
  State<IssuesPage> createState() => _IssuesPageState();
}

class _IssuesPageState extends State<IssuesPage> {
  bool ld = true;
  List projects = [];
  List issues = [];
  int? pid;
  final title = TextEditingController(), desc = TextEditingController();
  String severity = 'low', category = 'safety';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    title.dispose(); desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
      issues = await ApiService().getIssues(status: 'open');
    } catch (e) {
      toast('Failed to load issues: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _submit() async {
    if (pid == null && projects.isNotEmpty) pid = projects.first['project_id'];
    if (pid == null) { toast('Create a project first'); return; }
    if (title.text.trim().isEmpty) { toast('Please enter a short issue title'); return; }
    try {
      await ApiService().createIssue({
        'title': title.text.trim(), 'description': desc.text.trim().isEmpty ? title.text.trim() : desc.text.trim(),
        'project_id': pid, 'priority': severity, 'incident_type': category, 'is_safety_incident': category == 'safety',
      });
      title.clear(); desc.clear();
      toast('✅ Issue reported');
      _load();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to report issue');
    }
  }

  Future<void> _resolve(int id) async {
    try {
      await ApiService().resolveIssue(id);
      toast('✅ Marked as resolved');
      _load();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to update issue');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    pid ??= projects.isNotEmpty ? projects.first['project_id'] : null;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Report an Issue', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 14),
            if (projects.length > 1) ...[
              DropdownButtonFormField<int>(
                initialValue: pid,
                decoration: const InputDecoration(labelText: 'Project'),
                items: projects.map<DropdownMenuItem<int>>((p) => DropdownMenuItem(value: p['project_id'], child: Text(p['project_name']))).toList(),
                onChanged: (v) => setState(() => pid = v),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Issue Title', hintText: 'Short description of the issue')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: _severities.map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1)))).toList(),
                  onChanged: (v) => setState(() => severity = v!),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat[0].toUpperCase() + cat.substring(1)))).toList(),
                  onChanged: (v) => setState(() => category = v!),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Detailed Description', hintText: 'Provide as much detail as possible...')),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size.fromHeight(48)),
              child: const Text('Report Issue'),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Active Issues', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        if (issues.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No issues reported. Looking good!', style: TextStyle(color: AppColors.textMuted))))
        else
          ...issues.map((iss) => sectionCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(iss['title'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                    statusPill(iss['priority'] ?? 'low'),
                  ]),
                  const SizedBox(height: 4),
                  Text(iss['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(children: [
                    statusPill(iss['incident_type'] ?? 'general'),
                    const Spacer(),
                    TextButton(onPressed: () => _resolve(iss['issue_id']), child: const Text('Mark Resolved')),
                  ]),
                ]),
              )),
      ]),
    );
  }
}
