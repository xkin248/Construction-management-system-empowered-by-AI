import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

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

  List _projects = [];
  bool _loadingProjects = true;
  List _workers = [];
  bool _loadingWorkers = true;
  int? _workerId;
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
    final assignedRaw = t?['assigned_workers'];
    if (assignedRaw is List && assignedRaw.isNotEmpty) {
      final first = assignedRaw.first;
      if (first is Map && first['worker_id'] is int) {
        _workerId = first['worker_id'] as int;
      }
    }
    if (t?['due_date'] != null && t!['due_date'].toString().isNotEmpty) {
      _due = DateTime.tryParse(t['due_date'].toString());
    }
    _loadProjects();
    _loadWorkers();
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

  Future<void> _loadWorkers() async {
    try {
      final pid = _projectId;
      _workers = await ApiService().getWorkers(pid: pid);
      final known = _workers.any((w) => w['worker_id'] == _workerId);
      if (!known) _workerId = null;
    } catch (_) {}
    if (mounted) setState(() => _loadingWorkers = false);
  }

  /// Picks a suitable worker automatically and fills the assignment field.
  Future<void> _autoAssign() async {
    if (_workers.isEmpty) {
      await _loadWorkers();
    }
    final pick = _pickWorker();
    if (pick == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('No workers available to assign'),
            backgroundColor: AppColors.red));
      }
      return;
    }
    setState(() => _workerId = pick);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auto-assigned to ${_workerName(pick)}'),
          backgroundColor: AppColors.green));
    }
  }

  int? _pickWorker() {
    if (_workers.isEmpty) return null;
    // Prefer a worker with a trade/role on file; fall back to the first.
    for (final w in _workers) {
      final id = w['worker_id'];
      if (id is num && ((w['trade'] as String?) ?? '').isNotEmpty) {
        return id as int;
      }
    }
    final first = _workers.first['worker_id'];
    return first is num ? first as int : null;
  }

  String _workerName(int? id) {
    for (final w in _workers) {
      if (w['worker_id'] == id) return (w['name'] as String?) ?? 'Worker';
    }
    return 'Worker';
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
    setState(() => _submitting = true);
    try {
      final data = {
        'task_name': _title.text.trim(),
        'description': _desc.text.trim(),
        'project_id': _projectId,
        'priority': _priority,
        'due_date': _due?.toIso8601String().split('T').first,
        'estimated_hours': double.tryParse(_hours.text.trim()) ?? 0,
        'worker_ids': _workerId != null ? [_workerId] : [],
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
                          onChanged: (v) {
                            setState(() => _projectId = v);
                            _loadWorkers();
                          },
                        ),
                  const SizedBox(height: 14),
                  // ── Assign Worker (manual dropdown + auto-assign) ──
                  _fieldLabel('Assign Worker'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _loadingWorkers
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: SizedBox(
                                  height: 14, width: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2)))
                          : DropdownButtonFormField<int>(
                              initialValue: _workerId,
                              isExpanded: true,
                              decoration: _inputDeco(null),
                              items: _workers
                                  .map<DropdownMenuItem<int>>((w) =>
                                      DropdownMenuItem(
                                          value: w['worker_id'],
                                          child: Text(w['name'] ?? '',
                                              style: GoogleFonts.outfit(
                                                  fontSize: 13))))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _workerId = v),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _submitting ? null : _autoAssign,
                      tooltip: 'Auto assign worker',
                      icon: Icon(Icons.auto_awesome_rounded,
                          size: 20, color: AppColors.accent),
                    ),
                  ]),
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
                                    : DateFormat('dd/MM/yy').format(_due!),
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
}
