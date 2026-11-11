import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/worker_ui.dart';
import 'worker_common_task_page.dart';
import 'worker_toolbox_page.dart';
import 'worker_toolbox_return_page.dart';
import 'worker_toolbox_take_page.dart';

/// Safety tab (reference sheet: bottom bar item 4).
///
/// Three blocks in the order a worker needs them on site:
///  1. today's safety state — how many of the three daily safety jobs are done,
///  2. the jobs themselves (briefing / toolbox / housekeeping) plus the tool
///     register (take out, bring back, what is still out),
///  3. report a safety issue — the only block that leaves the screen.
///
/// Every button that talks to the backend has a loading state and reports
/// success only after the server answers (Button Click UI Spec §2).
class WorkerSafetyPage extends StatefulWidget {
  const WorkerSafetyPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WorkerSafetyPage> createState() => _WorkerSafetyPageState();
}

class _WorkerSafetyPageState extends State<WorkerSafetyPage> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _tasks = [];
  int _outstandingTools = 0;
  int? _workerId;
  int? _projectId;
  String _projectName = '';

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool _isDone(Map<String, dynamic> t) {
    final s = (t['status'] ?? '').toString().toLowerCase();
    return s == 'done' || s == 'completed';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        final me = await ApiService().me();
        final wid = me['worker_id'];
        _workerId = wid is num ? wid.toInt() : (me['id'] is num ? (me['id'] as num).toInt() : null);
        if (_workerId != null) {
          final w = await ApiService().getWorker(_workerId!);
          final p = w['project'];
          if (p is Map) {
            _projectId = (p['project_id'] is num) ? (p['project_id'] as num).toInt() : null;
            _projectName = (p['project_name'] ?? '').toString();
          }
        }
      } catch (_) {
        // identity lookup is best-effort: the checklist still loads
      }

      final r = await ApiService().commonTasksToday();
      final raw = r['tasks'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }

      int outstanding = 0;
      try {
        outstanding = (await ApiService().toolboxOutstanding()).length;
      } catch (_) {
        outstanding = 0;
      }

      if (!mounted) return;
      setState(() {
        _tasks = list;
        _outstandingTools = outstanding;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openTask(Map<String, dynamic> t) async {
    final id = (t['instance_id'] as num?)?.toInt();
    if (id == null) return;
    final kind = (t['task_kind'] ?? '').toString();
    final done = _isDone(t);
    if (kind == 'toolbox') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerToolboxPage(dailyInstanceId: id, dailyDone: done),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerCommonTaskPage(
          instanceId: id,
          kind: kind,
          initialStatus: (t['status'] ?? 'pending').toString(),
        ),
      ));
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    await _load();
  }

  // â”€â”€ report a safety issue â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _reportIssue() async {
    if (_workerId == null || _projectId == null) {
      toast(wT(
          en: 'No site assigned to your account.',
          ms: 'Tiada tapak untuk akaun anda.',
          zh: '账号未关联工地。'));
      return;
    }

    const types = <String>[
      'unsafe_act',
      'unsafe_condition',
      'near_miss',
      'equipment_defect',
      'other',
    ];
    const labelsEn = <String>[
      'Unsafe act',
      'Unsafe condition',
      'Near miss',
      'Equipment defect',
      'Other',
    ];
    const labelsMs = <String>[
      'Perbuatan tidak selamat',
      'Keadaan tidak selamat',
      'Hampir kemalangan',
      'Kerosakan peralatan',
      'Lain-lain',
    ];
    const labelsZh = <String>['ä¸å®‰å…¨è¡Œä¸º', 'ä¸å®‰å…¨çŠ¶æ€', 'é™©è‚‡äº‹æ•…', 'è®¾å¤‡ç¼ºé™·', 'å…¶ä»–'];

    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),
          Text(
            wT(en: 'What did you see?', ms: 'Apa yang anda nampak?', zh: '您发现了什么？'),
            style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < types.length; i++)
            ListTile(
              leading: Icon(Icons.report_gmailerrorred_rounded,
                  size: 22, color: AppColors.danger),
              title: Text(
                wT(en: labelsEn[i], ms: labelsMs[i], zh: labelsZh[i]),
                style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(i),
            ),
          const SizedBox(height: 6),
        ]),
      ),
    );

    if (choice == null || !mounted) return;

    double lat = 0;
    double lng = 0;
    String? locError;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        } else {
          locError = wT(
              en: 'Location is blocked â€” the report will be sent without a GPS pin.',
              ms: 'Lokasi disekat â€” laporan dihantar tanpa pin GPS.',
              zh: '定位权限被拒，报告将在无 GPS 坐标的情况下提交。');
        }
      } else {
        locError = wT(
            en: 'GPS is off â€” the report will be sent without a GPS pin.',
            ms: 'GPS dimatikan â€” laporan dihantar tanpa pin GPS.',
            zh: 'GPS 未开启，报告将在无 GPS 坐标的情况下提交。');
      }
    } catch (_) {
      locError = wT(
          en: 'Could not read GPS â€” the report will be sent without a GPS pin.',
          ms: 'Tidak dapat baca GPS â€” laporan dihantar tanpa pin.',
          zh: '无法获取 GPS，报告将在无坐标的情况下提交。');
    }

    if (!mounted) return;
    if (locError != null) toast(locError);

    final ok = await confirmDestructive(
      context,
      title: wT(en: 'Send safety report?', ms: 'Hantar laporan keselamatan?', zh: '提交安全报告？'),
      message: wT(
        en: 'Your supervisor is notified immediately with your name, time and location.',
        ms: 'Penyelia anda dimaklumkan serta-merta dengan nama, masa dan lokasi anda.',
        zh: '监理将立即收到您的姓名、时间与位置信息。',
      ),
      confirmLabel: wT(en: 'Send Report', ms: 'Hantar', zh: '提交报告'),
    );
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService().reportSafety(
        t: types[choice],
        w: _workerId!,
        p: _projectId!,
        lat: lat,
        lng: lng,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          wT(en: 'Safety report sent', ms: 'Laporan dihantar', zh: '安全报告已提交'),
          style: GoogleFonts.inter(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.onAccent),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(
          readableError(e),
          style: GoogleFonts.inter(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.onAccent),
        ),
      ));
    }
  }

  // â”€â”€ UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accentSolid,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          AppPageIntro(
            icon: Icons.health_and_safety_rounded,
            enTitle: 'STAY SAFE',
            msTitle: 'KERJA SELAMAT',
            zhTitle: '安全工作',
            enSubtitle: 'Daily safety checks and reports',
            msSubtitle: 'Semakan dan laporan keselamatan',
            zhSubtitle: '每日安全检查与报告',
            worker: true,
          ),
          const SizedBox(height: 14),
                    _statusCard(),
          const SizedBox(height: 12),
          _dailyBlock(),
          const SizedBox(height: 12),
          _toolboxBlock(),
          const SizedBox(height: 12),
          _reportBlock(),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(
          wT(en: 'SAFETY', ms: 'KESELAMATAN', zh: '安全'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ),
      body: body,
    );
  }

  Widget _card({required Widget child, Color? accent}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: accent ?? AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: child,
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
            color: AppColors.textMuted),
      );

  Widget _statusCard() {
    final total = _tasks.length;
    final done = _tasks.where(_isDone).length;
    final complete = total > 0 && done == total;
    final tint = _error != null
        ? AppColors.danger
        : complete
            ? AppColors.success
            : AppColors.accentSolid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: tint.withValues(alpha: 0.35)),
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(
              _error != null ? Icons.gpp_bad_rounded : Icons.health_and_safety_rounded,
              size: 23,
              color: tint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _error != null
                    ? wT(en: 'Safety data unavailable', ms: 'Data keselamatan tiada', zh: '安全数据不可用')
                    : complete
                        ? wT(en: "Today's safety is done", ms: 'Keselamatan hari ini selesai', zh: '今日安全项已完成')
                        : wT(en: "Today's safety tasks", ms: 'Tugasan keselamatan hari ini', zh: '今日安全任务'),
                style: GoogleFonts.inter(
                    fontSize: 15.5, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                _projectName.isEmpty
                    ? wT(en: 'No site assigned', ms: 'Tiada tapak', zh: '未分配工地')
                    : _projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
            ]),
          ),
          if (_error == null)
            Text(
              '$done/$total',
              style: GoogleFonts.inter(
                  fontSize: 22, fontWeight: FontWeight.w900, color: tint),
            ),
        ]),
        if (_error == null && total > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 7,
              backgroundColor: AppColors.bgMain,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppButton(
            label: wT(en: 'Try Again', ms: 'Cuba Lagi', zh: '重试'),
            tone: AppButtonTone.secondary,
            height: 42,
            onPressed: _load,
          ),
        ],
      ]),
    );
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'briefing':
        return wT(en: 'Site briefing', ms: 'Taklimat tapak', zh: '工地晨会');
      case 'toolbox':
        return wT(en: 'Toolbox check', ms: 'Semakan kotak alat', zh: '工具箱检查');
      case 'housekeeping':
        return wT(en: 'Housekeeping', ms: 'Kebersihan tapak', zh: '场地清理');
      default:
        return kind.isEmpty ? wT(en: 'Safety task', ms: 'Tugasan', zh: '安全任务') : kind;
    }
  }

  Widget _dailyBlock() {
    if (_loading) {
      return _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ),
      );
    }
    if (_tasks.isEmpty) {
      return _card(
        child: WEmpty(
          icon: Icons.health_and_safety_outlined,
          title: wT(en: 'NO SAFETY TASKS', ms: 'TIADA TUGASAN', zh: '暂无安全任务'),
          actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
          onAction: _load,
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: _label(wT(en: 'Daily safety jobs', ms: 'Tugasan harian', zh: '每日安全事项')),
      ),
      for (final t in _tasks) ...[
        _taskRow(t),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _taskRow(Map<String, dynamic> t) {
    final done = _isDone(t);
    final kind = (t['task_kind'] ?? '').toString();
    final tint = done ? AppColors.success : AppColors.accentSolid;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTask(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.rXl,
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.sm,
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              kind == 'toolbox'
                  ? Icons.handyman_rounded
                  : kind == 'housekeeping'
                      ? Icons.cleaning_services_rounded
                      : Icons.groups_rounded,
              size: 19,
              color: tint,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _kindLabel(kind),
                style: GoogleFonts.inter(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 3),
              Row(children: [
                Icon(done ? Icons.verified_rounded : Icons.schedule_rounded,
                    size: 13, color: tint),
                const SizedBox(width: 4),
                Text(
                  done
                      ? wT(en: 'Completed', ms: 'Selesai', zh: '已完成')
                      : wT(en: 'Pending', ms: 'Belum selesai', zh: '待完成'),
                  style: GoogleFonts.inter(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: tint),
                ),
              ]),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  Widget _toolboxBlock() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _label(wT(en: 'Toolbox register', ms: 'Daftar alat', zh: '工具登记')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (_outstandingTools > 0 ? AppColors.warning : AppColors.success)
                  .withValues(alpha: 0.12),
              borderRadius: AppRadius.rPill,
            ),
            child: Text(
              wT(
                  en: '$_outstandingTools out',
                  ms: '$_outstandingTools keluar',
                  zh: '未归还 $_outstandingTools'),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: _outstandingTools > 0 ? AppColors.warning : AppColors.success,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: AppButton(
              label: wT(en: 'Take Tools', ms: 'Ambil Alat', zh: '取用工具'),
              tone: AppButtonTone.secondary,
              height: 44,
              icon: Icons.outbox_rounded,
              onPressed: () => _open(const WorkerToolboxTakePage()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              label: wT(en: 'Return Tools', ms: 'Pulang Alat', zh: '归还工具'),
              tone: AppButtonTone.secondary,
              height: 44,
              icon: Icons.move_to_inbox_rounded,
              onPressed: () => _open(const WorkerToolboxReturnPage()),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          wT(
            en: 'Every tool out and back needs one photo of the tray.',
            ms: 'Setiap alat keluar dan masuk perlu satu foto dulang.',
            zh: '每次取用与归还都需拍摄一张工具箱照片。',
          ),
          style: GoogleFonts.inter(
              fontSize: 11.5, height: 1.3, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  Widget _reportBlock() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redLight,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.campaign_rounded, size: 20, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wT(en: 'See something unsafe?', ms: 'Nampak sesuatu tidak selamat?', zh: '发现安全隐患？'),
              style: GoogleFonts.inter(
                  fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          wT(
            en: 'Report it right away. Your supervisor is alerted with your location.',
            ms: 'Laporkan segera. Penyelia dimaklumkan dengan lokasi anda.',
            zh: '请立即上报，监理会收到您的位置信息。',
          ),
          style: GoogleFonts.inter(
              fontSize: 12, height: 1.35, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: wT(en: 'Report Safety Issue', ms: 'Lapor Isu Keselamatan', zh: '上报安全问题'),
          tone: AppButtonTone.destructive,
          height: 48,
          icon: Icons.warning_amber_rounded,
          onPressed: _reportIssue,
        ),
      ]),
    );
  }
}
