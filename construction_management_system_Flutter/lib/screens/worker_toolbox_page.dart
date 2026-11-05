import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_ui.dart';
import 'worker_toolbox_return_page.dart';
import 'worker_toolbox_take_page.dart';

/// Toolbox hub — two big doors: take tools out, bring tools back.
///
/// What is still out is shown as one big number plus its names, because that is
/// the only question a worker ever asks about the toolbox ("what do I still
/// have?"). Both sub-pages require a photo before anything is sent.
class WorkerToolboxPage extends StatefulWidget {
  /// Today's `toolbox` common-task instance, forwarded to the take page so the
  /// hand-over photo can also tick the daily checklist item.
  final int? dailyInstanceId;
  final bool dailyDone;

  const WorkerToolboxPage({
    super.key,
    this.dailyInstanceId,
    this.dailyDone = false,
  });

  @override
  State<WorkerToolboxPage> createState() => _WorkerToolboxPageState();
}

class _WorkerToolboxPageState extends State<WorkerToolboxPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _outstanding = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ApiService().toolboxOutstanding();
      if (!mounted) return;
      setState(() {
        _outstanding = rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _apiError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _apiError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is String && data.isNotEmpty) return data;
    return e.message ?? 'Request failed';
  }

  Future<void> _openTake() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerToolboxTakePage(
        dailyInstanceId: widget.dailyInstanceId,
        dailyDone: widget.dailyDone,
      ),
    ));
    if (mounted) await _load();
  }

  Future<void> _openReturn() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const WorkerToolboxReturnPage(),
    ));
    if (mounted) await _load();
  }

  int get _totalQty => _outstanding.fold<int>(
      0, (sum, r) => sum + ((r['qty'] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: Text(
          wT(en: 'TOOLBOX', ms: 'TOOLBOX', zh: '工具箱'),
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            iconSize: 28,
            color: AppColors.textSecondary,
            tooltip: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: ListView(children: [
            WNumberTile(
              icon: Icons.inventory_2_rounded,
              value: '$_totalQty',
              label: wT(en: 'OUT NOW', ms: 'KELUAR', zh: '未归还'),
              color: _totalQty > 0 ? AppColors.yellow : AppColors.green,
            ),
            const SizedBox(height: 14),
            WBigAction(
              icon: Icons.handyman_rounded,
              label: wT(en: 'TAKE TOOLS', ms: 'AMBIL ALAT', zh: '领取工具'),
              color: AppColors.accent,
              height: 96,
              onTap: _openTake,
            ),
            const SizedBox(height: 12),
            WBigAction(
              icon: Icons.assignment_return_rounded,
              label: wT(en: 'RETURN TOOLS', ms: 'PULANG ALAT', zh: '归还工具'),
              color: AppColors.green,
              height: 96,
              onTap: _openReturn,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              WErrorHint(
                title: wT(en: 'NO CONNECTION', ms: 'TIADA SAMBUNGAN', zh: '连接失败'),
                hint: _error!,
                onRetry: _load,
              )
            else if (_outstanding.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  wT(
                    en: 'Nothing out. All tools are back.',
                    ms: 'Tiada alat keluar. Semua sudah pulang.',
                    zh: '没有未归还的工具，全部已归还',
                  ),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  wT(en: 'STILL OUT', ms: 'MASIH KELUAR', zh: '仍未归还'),
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary),
                ),
              ),
              for (final row in _outstanding) ...[
                _outRow(row),
                const SizedBox(height: 8),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _outRow(Map<String, dynamic> row) {
    final qty = (row['qty'] as num?)?.toInt() ?? 0;
    return Container(
      constraints: const BoxConstraints(minHeight: kWRowTap),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.yellowLight,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.handyman_rounded, size: 22, color: AppColors.yellow),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            (row['tool_name'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'x$qty',
          style: GoogleFonts.inter(
              fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ]),
    );
  }
}
