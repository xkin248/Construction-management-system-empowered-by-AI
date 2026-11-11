import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/trade_levels.dart';
import '../constants/specialties.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../theme/app_theme.dart';
import '../utils/date_helper.dart';

/// Supervisor task form (create + edit).
///
/// Sections follow the Tasks Management reference: basics, requirement (one of
/// the four skill levels + required head count), schedule (start / due date)
/// and assignment.
///
/// AI Auto-Assign never writes anything by itself: pressing it only fetches
/// ranked workers (GET /ai/tasks/match) and shows name, skill level, match
/// score, today\'s availability and the reason, pre-selecting the top N. The
/// supervisor can add or drop anyone before submitting; the assignment is
/// persisted only through the normal create / update call with `worker_ids`.
class TaskForm extends StatefulWidget {
  final Map<String, dynamic>? task;
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

  DateTime? _start;
  DateTime? _due;
  int? _projectId;
  String _priority = 'medium';
  String? _trade;
  String? _requiredSpecialty;

  List _projects = [];
  List<Map<String, dynamic>> _workers = [];
  final Map<int, String> _todayStatus = {};
  final Set<int> _selectedWorkerIds = {};

  int _requiredWorkers = 1;
  bool _assignmentTouched = false;

  bool _loadingProjects = true;
  bool _loadingWorkers = false;
  bool _submitting = false;
  bool _aiBusy = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?['task_name'] ?? '');
    _desc = TextEditingController(text: t?['description'] ?? '');
    _hours = TextEditingController(text: t?['estimated_hours']?.toString() ?? '');
    _priority = t?['priority'] as String? ?? 'medium';
    _projectId = t?['project_id'] as int? ?? widget.initialProjectId;
    _trade = TradeLevels.normalise(t?['trade'] as String?);
    _requiredSpecialty = t?['required_specialty'] as String?;

    if (t?['due_date'] != null && t!['due_date'].toString().isNotEmpty) {
      _due = DateTime.tryParse(t['due_date'].toString());
    }
    if (t?['started_at'] != null && t!['started_at'].toString().isNotEmpty) {
      _start = DateTime.tryParse(t['started_at'].toString());
    }
    final assigned = t?['assigned_workers'];
    if (assigned is List) {
      for (final row in assigned) {
        if (row is Map && row['worker_id'] != null) {
          _selectedWorkerIds.add(row['worker_id'] as int);
        }
      }
    }
    if (_selectedWorkerIds.isNotEmpty) _requiredWorkers = _selectedWorkerIds.length;

    _loadProjects();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _hours.dispose();
    super.dispose();
  }

  // ──────────────── data ────────────────

  Future<void> _loadProjects() async {
    try {
      _projects = await ProjectCache.get(ApiService(), forceRefresh: true);
      final validIds = _projects
          .map((p) => p['project_id'])
          .whereType<int>()
          .toSet();
      // A modal can outlive a project deletion. Never submit a stale ID.
      if (_projectId != null && !validIds.contains(_projectId)) {
        _projectId = null;
      }
      if (!_isEdit && _projects.isNotEmpty && _projectId == null) {
        _projectId = _projects.first['project_id'];
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProjects = false);
    await _loadWorkers();
  }

  /// Workers of the selected project + today\'s attendance, so the picker can
  /// show availability next to each name. Failures are silent: the supervisor
  /// can still create the task and assign workers later.
  Future<void> _loadWorkers() async {
    final pid = _projectId;
    if (pid == null) return;
    setState(() => _loadingWorkers = true);
    List workers = [];
    Map attendance = {};
    try {
      final res = await Future.wait([
        ApiService().getWorkers(pid: pid),
        ApiService().attendanceToday(pid: pid),
      ]);
      workers = res[0] as List;
      attendance = res[1] as Map;
    } catch (_) {}
    if (!mounted) return;
    final rows = (attendance['rows'] ?? attendance['workers'] ?? attendance['records'] ?? []) as List;
    _todayStatus.clear();
    for (final r in rows) {
      if (r is Map && r['worker_id'] != null) {
        _todayStatus[r['worker_id'] as int] =
            (r['today_status'] ?? r['status'] ?? '').toString();
      }
    }
    setState(() {
      _loadingWorkers = false;
      _workers = workers
          .whereType<Map>()
          .map((w) => Map<String, dynamic>.from(w))
          .toList();
      // Drop selections that no longer belong to the project.
      final ids = _workers.map((w) => w['worker_id'] as int?).toSet();
      _selectedWorkerIds.removeWhere((id) => !ids.contains(id));
    });
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: AppSettings.t('Planned start', '计划开始日期', 'Mula dirancang'),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: AppSettings.t('Due date', '截止日期', 'Tarikh akhir'),
    );
    if (d != null) setState(() => _due = d);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ──────────────── AI auto-assign (suggest, then confirm) ────────────────

  double? _scoreOf(Map m) {
    for (final k in ['score', 'match_score', 'final_score', 'confidence']) {
      final v = m[k];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  String _reasonOf(Map m) =>
      (m['reason'] ?? m['explanation'] ?? m['why'] ?? m['note'] ?? '').toString();

  Future<void> _openAiSuggest() async {
    if (_trade == null) {
      _say(AppSettings.t(
        'Pick a required skill level first — AI matches workers by level.',
        '请先选择所需技能等级，AI 会按等级匹配工人。',
        'Pilih tahap kemahiran dahulu — AI memadankan pekerja mengikut tahap.',
      ));
      return;
    }
    final pid = _projectId;
    if (pid == null) {
      _say(AppSettings.t('Select a project first', '请先选择项目', 'Pilih projek dahulu'));
      return;
    }
    setState(() => _aiBusy = true);
    List raw = [];
    try {
      raw = await ApiService().aiTaskMatch(_trade!, pid, requiredSpecialty: _requiredSpecialty);
    } catch (e) {
      if (mounted) setState(() => _aiBusy = false);
      _say(AppSettings.t(
        'AI suggestions are unavailable right now — pick workers manually.',
        '暂时无法获取 AI 推荐，请手动选择工人。',
        'Cadangan AI tidak tersedia sekarang — pilih pekerja secara manual.',
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _aiBusy = false);

    final suggestions = raw.whereType<Map>().map((r) {
      final m = Map<String, dynamic>.from(r);
      final id = m['worker_id'];
      if (id is num) {
        m['today_status'] = _todayStatus[id.toInt()] ?? 'absent';
      }
      return m;
    }).where((m) => m['worker_id'] != null).toList();

    if (suggestions.isEmpty) {
      _say(AppSettings.t(
        'No worker matches this skill level in the project.',
        '项目内没有匹配该技能等级的工人。',
        'Tiada pekerja sepadan dengan tahap kemahiran ini.',
      ));
      return;
    }

    final picked = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _SuggestionDialog(
        suggestions: suggestions,
        defaultCount: _requiredWorkers,
        requiredLabel: _levelLabel(_trade),
        scoreOf: _scoreOf,
        reasonOf: _reasonOf,
        availabilityLabel: _availabilityLabel,
        availabilityColor: _availabilityColor,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedWorkerIds
        ..clear()
        ..addAll(picked);
      _assignmentTouched = true;
    });
    _say(AppSettings.t(
      'Recommendation applied — adjust the list if needed, then create the task.',
      '已套用推荐，可继续人工调整后再创建任务。',
      'Cadangan digunakan — laraskan jika perlu, kemudian cipta tugas.',
    ));
  }

  // ──────────────── labels ────────────────

  String _levelLabel(String? raw) =>
      TradeLevels.label(TradeLevels.normalise(raw) ?? raw);

  String _availabilityLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'present':
      case 'checked_in':
      case 'on_site':
      case 'on time':
        return AppSettings.t('On site today', '今日在场', 'Hadir hari ini');
      case 'late':
        return AppSettings.t('Checked in late', '今日迟到', 'Daftar lewat');
      default:
        return AppSettings.t('Not checked in', '未签到', 'Belum daftar masuk');
    }
  }

  Color _availabilityColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'present':
      case 'checked_in':
      case 'on_site':
      case 'on time':
        return AppColors.green;
      case 'late':
        return AppColors.yellow;
      default:
        return AppColors.textMuted;
    }
  }

  // ──────────────── submit ────────────────

  Future<void> _submit() async {
    if (!(_fk.currentState?.validate() ?? false)) return;
    if (_projectId == null) {
      _say(AppSettings.t('Select a project first', '请先选择项目', 'Pilih projek dahulu'));
      return;
    }
    if (_start != null && _due != null && _start!.isAfter(_due!)) {
      _say(AppSettings.t(
        'The start date must be before the due date.',
        '开始日期不能晚于截止日期。',
        'Tarikh mula mesti sebelum tarikh akhir.',
      ));
      return;
    }
    final name = _title.text.trim();
    final desc = _desc.text.trim();
    final vague = _isVagueText(name) || (desc.isNotEmpty && _isVagueText(desc));
    if (_trade == null && vague) {
      final proceed = await _confirmVagueSubmission();
      if (proceed != true || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      final data = <String, dynamic>{
        'task_name': name,
        'description': desc,
        'project_id': _projectId,
        'priority': _priority,
        'due_date': _due?.toIso8601String().split('T').first,
        'estimated_hours': double.tryParse(_hours.text.trim()) ?? 0,
        if (_trade != null) 'trade': _trade,
        if (_requiredSpecialty != null) 'required_specialty': _requiredSpecialty,
        if (_start != null) 'started_at': _start!.toIso8601String(),
      };
      // Send the assignment only when it is meaningful: on create always, on
      // edit only after the supervisor touched the list — otherwise an empty
      // selection (e.g. workers failed to load) would wipe the existing crew.
      if (!_isEdit || _assignmentTouched || _selectedWorkerIds.isNotEmpty) {
        data['worker_ids'] = _selectedWorkerIds.toList();
      }
      if (_isEdit) {
        await ApiService().updateTask(widget.task!['task_id'], data);
      } else {
        await ApiService().createTask(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      _say('${AppSettings.t('Failed to save task', '任务保存失败', 'Gagal menyimpan tugas')}: $e');
    }
  }

  // ──────────────── build ────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Form(
            key: _fk,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        _isEdit
                            ? AppSettings.t('Edit Task', '编辑任务', 'Sunting Tugas')
                            : AppSettings.t('New Task', '新建任务', 'Tugas Baharu'),
                        style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
                      tooltip: AppStrings.t('common.cancel'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _sectionLabel('BASICS', '基本信息', 'ASAS'),
                  const SizedBox(height: 8),
                  _fieldLabel(AppSettings.t('Task Name', '任务名称', 'Nama Tugas')),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _title,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                    decoration: _inputDeco(
                        AppSettings.t('e.g. Foundation Pile Driving', '例如：基础打桩', 'cth. Pemancangan Cerucuk')),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel(AppSettings.t('Description', '任务描述', 'Penerangan')),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _desc,
                    maxLines: 2,
                    decoration: _inputDeco(
                        AppSettings.t('Optional description...', '可选描述...', 'Penerangan pilihan...')),
                  ),
                  const SizedBox(height: 16),
                  _sectionLabel('REQUIREMENT', '技能要求', 'KEPERLUAN'),
                  const SizedBox(height: 8),
                  _fieldLabel(AppSettings.t('Project', '项目', 'Projek')),
                  const SizedBox(height: 6),
                  _loadingProjects
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _projectId,
                          isExpanded: true,
                          decoration: _inputDeco(null),
                          items: _projects
                              .map<DropdownMenuItem<int>>((p) => DropdownMenuItem(
                                    value: p['project_id'] as int,
                                    child: Text(p['project_name'] ?? '',
                                        style: GoogleFonts.inter(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == _projectId) return;
                            setState(() {
                              _projectId = v;
                              _workers = [];
                              _todayStatus.clear();
                              _selectedWorkerIds.clear();
                              _assignmentTouched = true;
                            });
                            _loadWorkers();
                          },
                        ),
                  const SizedBox(height: 14),
                  _fieldLabel(
                      AppSettings.t('Required Skill Level', '所需技能等级', 'Tahap Kemahiran Diperlukan')),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _levelChip(null, AppSettings.t('Any', '不限', 'Mana-mana')),
                      ...TradeLevels.all.map((l) => _levelChip(l.value, l.label)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _requiredSpecialty,
                    isExpanded: true,
                    decoration: _inputDeco('Required specialty (optional)'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Any specialty')),
                      ...Specialties.all.map((specialty) => DropdownMenuItem<String>(
                        value: specialty,
                        child: Text(Specialties.label(specialty)),
                      )),
                    ],
                    onChanged: (value) => setState(() => _requiredSpecialty = value),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _fieldLabel(
                          AppSettings.t('Workers Needed', '所需工人数', 'Bilangan Pekerja')),
                    ),
                    _stepper(),
                  ]),
                  const SizedBox(height: 16),
                  _sectionLabel('SCHEDULE', '起止日期', 'JADUAL'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                              AppSettings.t('Start Date', '开始日期', 'Tarikh Mula')),
                          const SizedBox(height: 6),
                          _dateButton(_start, _pickStart),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                              AppSettings.t('Due Date', '截止日期', 'Tarikh Akhir')),
                          const SizedBox(height: 6),
                          _dateButton(_due, _pickDate),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    AppSettings.t(
                      'The start date is the planned kick-off recorded on the task; the crew still only moves it to In Progress once work actually begins.',
                      '开始日期是记录在任务上的计划开工时间；实际开工仍由现场将任务推进为「进行中」时确认。',
                      'Tarikh mula ialah permulaan terancang yang direkodkan pada tugas; kerja sebenar tetap ditanda oleh pasukan.',
                    ),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(AppSettings.t('Priority', '优先级', 'Keutamaan')),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _priority,
                            decoration: _inputDeco(null),
                            items: const ['low', 'medium', 'high']
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p[0].toUpperCase() + p.substring(1),
                                          style: GoogleFonts.inter(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _priority = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                              AppSettings.t('Estimated Days', '预估天数', 'Anggaran Hari')),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _hours,
                            keyboardType: TextInputType.number,
                            decoration: _inputDeco('e.g. 10'),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _assignmentSection(),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                          ),
                          child: Text(
                            AppSettings.t('Cancel', '取消', 'Batal'),
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.accentInk,
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.accentInk))
                              : Text(
                                  _isEdit
                                      ? AppSettings.t('Save Changes', '保存修改', 'Simpan Perubahan')
                                      : AppSettings.t('Create Task', '创建任务', 'Cipta Tugas'),
                                  style: GoogleFonts.inter(
                                      fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────── assignment section ────────────────

  Widget _assignmentSection() {
    final needed = _requiredWorkers;
    final chosen = _selectedWorkerIds.length;
    final ready = chosen >= needed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: _sectionLabel('ASSIGNMENT', '指派工人', 'PENUGASAN')),
          OutlinedButton.icon(
            onPressed: _aiBusy ? null : _openAiSuggest,
            icon: _aiBusy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 15),
            label: Text(
              AppSettings.t('AI Auto-Assign', 'AI 自动分配', 'Auto Tugasan AI'),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text(
            '${AppSettings.t('Selected', '已选', 'Dipilih')} $chosen / $needed',
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ready ? AppColors.green : AppColors.textMuted),
          ),
          const Spacer(),
          if (_selectedWorkerIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _selectedWorkerIds.clear();
                _assignmentTouched = true;
              }),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppSettings.t('Clear all', '全部清除', 'Kosongkan'),
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        if (_loadingWorkers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_workers.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgMain,
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              AppSettings.t(
                'No workers in this project yet. Create the task now and assign the crew later.',
                '该项目暂无工人。可先创建任务，之后再指派工人。',
                'Tiada pekerja dalam projek ini. Cipta tugas dahulu dan tugaskan kemudian.',
              ),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 216),
            decoration: BoxDecoration(
              color: AppColors.bgMain,
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _workers.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
              itemBuilder: (_, i) => _workerRow(_workers[i]),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          AppSettings.t(
            'AI only recommends — the crew is assigned when you press Create Task, and you can change anyone on the list first.',
            'AI 只做推荐：按「创建任务」后才正式派工，可先任意修改名单。',
            'AI hanya mencadangkan — pasukan ditugaskan selepas anda tekan Cipta Tugas.',
          ),
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _workerRow(Map<String, dynamic> w) {
    final id = w['worker_id'] as int?;
    if (id == null) return const SizedBox.shrink();
    final selected = _selectedWorkerIds.contains(id);
    final status = _todayStatus[id];
    return InkWell(
      onTap: () => setState(() {
        _assignmentTouched = true;
        if (selected) {
          _selectedWorkerIds.remove(id);
        } else {
          _selectedWorkerIds.add(id);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          Icon(
            selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            size: 18,
            color: selected ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                (w['name'] ?? w['worker_name'] ?? '-').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.engineering_outlined, size: 11, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _levelLabel(w['trade'] as String?),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: _availabilityColor(status), shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              _availabilityLabel(status),
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
            ),
          ]),
        ]),
      ),
    );
  }

  // ──────────────── small pieces ────────────────

  Widget _stepper() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _stepButton(Icons.remove, _requiredWorkers > 1, () {
        setState(() => _requiredWorkers = _requiredWorkers - 1);
      }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('$_requiredWorkers',
            style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      _stepButton(Icons.add, _requiredWorkers < 20, () {
        setState(() => _requiredWorkers = _requiredWorkers + 1);
      }),
    ]);
  }

  Widget _stepButton(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: AppRadius.rMd,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: AppRadius.rMd,
          border: Border.all(color: AppColors.border),
          color: enabled ? AppColors.bgCard : AppColors.bgMain,
        ),
        child: Icon(icon,
            size: 15,
            color: enabled ? AppColors.textSecondary : AppColors.textMuted),
      ),
    );
  }

  Widget _levelChip(String? value, String label) {
    final active = _trade == value;
    return GestureDetector(
      onTap: () => setState(() => _trade = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.12) : AppColors.bgMain,
          borderRadius: AppRadius.rPill,
          border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
              width: active ? 1.4 : 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.accent : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _dateButton(DateTime? value, VoidCallback onTap) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined, size: 15),
        label: Text(
          value == null
              ? AppSettings.t('Select', '选择', 'Pilih')
              : DateHelper.formatShort(value),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: value == null ? AppColors.textMuted : AppColors.textSecondary,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }

  Widget _sectionLabel(String en, String zh, String ms) => Text(
        AppSettings.t(en, zh, ms),
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textMuted),
      );

  Widget _fieldLabel(String text) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary));

  InputDecoration _inputDeco(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.bgMain,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.accent)),
        errorBorder: OutlineInputBorder(
            borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.red)),
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
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        title: Text(
          AppSettings.t('Task info too vague', '任务信息过于模糊', 'Maklumat tugas terlalu kabur'),
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppSettings.t(
            'This task name or description looks like a placeholder. Without a clear name or a required skill level, the crew and the AI cannot tell what the work is.',
            '任务名称或描述看起来像占位内容。没有明确名称或技能等级时，工人与 AI 都无法判断这是什么工作。',
            'Nama atau penerangan tugas kelihatan seperti pemegang tempat. Tanpa nama atau tahap kemahiran, pasukan tidak tahu kerja sebenar.',
          ),
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppSettings.t('Go back', '返回修改', 'Kembali')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppSettings.t('Create anyway', '仍然创建', 'Cipta juga')),
          ),
        ],
      ),
    );
  }
}

/// AI recommendation sheet: name, level, match score, today\'s availability and
/// the reason, all pre-selected up to the required head count. Returns the
/// supervisor-confirmed worker ids (null = cancelled).
class _SuggestionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> suggestions;
  final int defaultCount;
  final String requiredLabel;
  final double? Function(Map) scoreOf;
  final String Function(Map) reasonOf;
  final String Function(String?) availabilityLabel;
  final Color Function(String?) availabilityColor;

  const _SuggestionDialog({
    required this.suggestions,
    required this.defaultCount,
    required this.requiredLabel,
    required this.scoreOf,
    required this.reasonOf,
    required this.availabilityLabel,
    required this.availabilityColor,
  });

  @override
  State<_SuggestionDialog> createState() => _SuggestionDialogState();
}

class _SuggestionDialogState extends State<_SuggestionDialog> {
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    for (final s in widget.suggestions.take(widget.defaultCount)) {
      final id = s['worker_id'];
      if (id is num) _picked.add(id.toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
      insetPadding: const EdgeInsets.all(24),
      title: Row(children: [
        Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppSettings.t('AI recommendations', 'AI 推荐工人', 'Cadangan AI'),
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppSettings.t(
                'Matched on the required level (${widget.requiredLabel}) and today\'s attendance. Nothing is assigned until you confirm and create the task.',
                '按所需等级（${widget.requiredLabel}）与今日出勤匹配。确认并创建任务后才会正式派工。',
                'Dipadankan dengan tahap diperlukan (${widget.requiredLabel}) dan kehadiran hari ini.',
              ),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
                itemBuilder: (_, i) {
                  final s = widget.suggestions[i];
                  final id = (s['worker_id'] as num).toInt();
                  final on = _picked.contains(id);
                  final score = widget.scoreOf(s);
                  final pct = score == null
                      ? null
                      : (score <= 1 ? score * 100 : score).clamp(0, 100).round();
                  final status = (s['today_status'] ?? '').toString();
                  return InkWell(
                    onTap: () => setState(() {
                      if (on) {
                        _picked.remove(id);
                      } else {
                        _picked.add(id);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(
                          on
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color: on ? AppColors.accent : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      (s['name'] ?? s['worker_name'] ?? '-').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                          fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (pct != null)
                                    Text('$pct%',
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.accent)),
                                ]),
                                const SizedBox(height: 3),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  _miniChip(
                                      TradeLevels.label(
                                          (s['trade_level'] ?? s['trade'] ?? '').toString()),
                                      AppColors.accent,
                                      AppColors.textMuted),
                                  _miniChip(
                                    widget.availabilityLabel(status),
                                    widget.availabilityColor(status),
                                    widget.availabilityColor(status),
                                  ),
                                ]),
                                if (widget.reasonOf(s).isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.reasonOf(s),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ],
                              ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppSettings.t('Cancel', '取消', 'Batal')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _picked),
          child: Text(
            '${AppSettings.t('Use selected', '使用所选', 'Guna pilihan')} (${_picked.length})',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _miniChip(String text, Color fg, Color dot) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: AppRadius.rPill,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text,
            style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}
