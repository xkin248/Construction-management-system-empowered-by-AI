import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/date_helper.dart';

class TaskForm extends StatefulWidget {
  /// Pre-filled task data for edit mode; null for create mode.
  final Map<String, dynamic>? task;

  /// Pre-selected project id (used when creating from a filtered project view).
  final int? initialProjectId;

  const TaskForm({super.key, this.task, this.initialProjectId});

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _fk = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _hours;
  DateTime? _due;
  int? _projectId;
  String _priority = 'medium';
  String? _trade;

  List _projects = [];
  bool _loadingProjects = true;
  bool _submitting = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?['task_name'] ?? '');
    _desc = TextEditingController(text: t?['description'] ?? '');
    _hours = TextEditingController(
        text: t?['estimated_hours']?.toString() ?? '');
    _priority = t?['priority'] as String? ?? 'medium';
    _projectId = t?['project_id'] as int? ?? widget.initialProjectId;
    _trade = t?['trade'] as String?;
    if (t?['due_date'] != null && t!['due_date'].toString().isNotEmpty) {
      _due = DateTime.tryParse(t['due_date'].toString());
    }
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      _projects = await ApiService().getProjects();
      if (!_isEdit && _projects.isNotEmpty && _projectId == null) {
        _projectId = _projects.first['project_id'];
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProjects = false);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _submit() async {
    if (!(_fk.currentState?.validate() ?? false)) return;
    // Pre-flight guard: placeholder-ish task text without an explicit trade
    // would be skipped by AI Auto-Assign. Let the user choose instead of
    // silently creating a task that can never be auto-assigned.
    final title = _title.text.trim();
    final desc = _desc.text.trim();
    final vague =
        _isVagueText(title) || (desc.isNotEmpty && _isVagueText(desc));
    if (_trade == null && vague) {
      final proceed = await _confirmVagueSubmission();
      if (proceed != true || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      final data = {
        'task_name': title,
        'description': desc,
        'project_id': _projectId,
        'priority': _priority,
        'due_date': _due?.toIso8601String().split('T').first,
        'estimated_hours': double.tryParse(_hours.text.trim()) ?? 0,
        if (_trade != null) 'trade': _trade,
      };
      if (_isEdit) {
        await ApiService().updateTask(widget.task!['task_id'], data);
      } else {
        await ApiService().createTask(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e'), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Form(
            key: _fk,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(_isEdit ? 'Edit Task' : 'New Task',
                          style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 20, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // ── Title ──
                  _fieldLabel('Task Title'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _title,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                    decoration: _inputDeco('e.g. Foundation Pile Driving'),
                  ),
                  const SizedBox(height: 14),
                  // ── Description ──
                  _fieldLabel('Description'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _desc,
                    maxLines: 2,
                    decoration: _inputDeco('Optional description...'),
                  ),
                  const SizedBox(height: 14),
                  // ── Project ──
                  _fieldLabel('Project'),
                  const SizedBox(height: 6),
                  _loadingProjects
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : DropdownButtonFormField<int>(
                          initialValue: _projectId,
                          isExpanded: true,
                          decoration: _inputDeco(null),
                          items: _projects
                              .map<DropdownMenuItem<int>>((p) =>
                                  DropdownMenuItem(
                                      value: p['project_id'],
                                      child: Text(p['project_name'] ?? '',
                                          style: GoogleFonts.outfit(
                                              fontSize: 13))))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _projectId = v),
                        ),
                  const SizedBox(height: 14),
                  // ── Required Trade ──
                  _fieldLabel('Required Trade'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _trade ?? '',
                    isExpanded: true,
                    decoration: _inputDeco(null),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text('None / Not sure',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: AppColors.textMuted)),
                      ),
                      ..._kTrades.map((t) => DropdownMenuItem(
                            value: t.$1,
                            child: Text(t.$2,
                                style:
                                    GoogleFonts.outfit(fontSize: 13)),
                          )),
                    ],
                    onChanged: (v) => setState(
                        () => _trade = (v == null || v.isEmpty) ? null : v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tip: selecting a trade lets AI Auto-Assign match workers by '
                    'trade instead of guessing from the task title.',
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  // ── Priority + Due Date row ──
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _fieldLabel('Priority'),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _priority,
                            decoration: _inputDeco(null),
                            items: const ['low', 'medium', 'high']
                                .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                        p[0].toUpperCase() + p.substring(1),
                                        style: GoogleFonts.outfit(
                                            fontSize: 13))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _priority = v!),
                          ),
                        ])),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _fieldLabel('Due Date'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16),
                              label: Text(
                                _due == null
                                    ? 'Select'
                                    : DateHelper.formatShort(_due!),
                                style: GoogleFonts.outfit(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                side:
                                    BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                              ),
                            ),
                          ),
                        ])),
                  ]),
                  const SizedBox(height: 14),
                  // ── Estimated Days ──
                  _fieldLabel('Estimated Days'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('e.g. 10'),
                  ),
                  const SizedBox(height: 24),
                  // ── Submit ──
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              _isEdit ? 'Save Changes' : 'Create Task',
                              style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text,
      style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary));

  InputDecoration _inputDeco(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.bgMain,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.accent)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.red)),
      );

  /// Heuristic: placeholder-ish text the AI would fail to interpret
  /// (empty, <3 chars, common junk words, or pure repeated characters).
  bool _isVagueText(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return true;
    if (s.length < 3) return true;
    final lower = s.toLowerCase();
    const placeholders = {
      'test', 'abc', 'xxx', 'asd', '123', 'todo', 'testing', 'testinggg',
      'test1', 'task', 'task1', 'demo', 'foo', 'bar', 'qwerty', 'lorem',
      'placeholder', 'n/a', 'na', 'none',
    };
    if (placeholders.contains(lower)) return true;
    final runs = lower.runes.toList();
    if (runs.length >= 3 && runs.every((r) => r == runs.first)) return true;
    return false;
  }

  Future<bool?> _confirmVagueSubmission() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Task info too vague — AI may not auto-assign'),
        content: const Text(
            'This task name/description looks like a placeholder (e.g. "test"). '
            'Without a clear name or an explicit Required Trade, AI Auto-Assign '
            'will skip this task instead of guessing, so it may stay unassigned.\n\n'
            'Add a specific task name/description, or pick a Required Trade above.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back to edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );
  }
}

/// Canonical trade values consumed by AI Auto-Assign (value = canonical lowercase).
const List<(String, String)> _kTrades = [
  ('carpenter', 'Carpenter'),
  ('electrical', 'Electrician'),
  ('plumbing', 'Plumber'),
  ('masonry', 'Mason'),
  ('painting', 'Painter'),
  ('welding', 'Welder'),
  ('hvac', 'HVAC Technician'),
  ('roofing', 'Roofer'),
  ('tiling', 'Tiler'),
  ('drywall', 'Drywall Installer'),
  ('glazing', 'Glazier'),
  ('flooring', 'Flooring Installer'),
  ('equipment', 'Equipment Operator'),
  ('laborer', 'General Laborer'),
  ('insulation', 'Insulation Installer'),
  ('supervision', 'Site Supervisor'),
];
