import 'package:dio/dio.dart';
import '../widgets/app_page_intro.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/photo_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_ui.dart';

/// Toolbox — bring tools back.
///
/// Everything still out is listed with its quantity; the worker taps the tools
/// being returned (or SELECT ALL) and takes one photo of them. That single
/// photo closes every selected issue on the server.
class WorkerToolboxReturnPage extends StatefulWidget {
  const WorkerToolboxReturnPage({super.key});

  @override
  State<WorkerToolboxReturnPage> createState() => _WorkerToolboxReturnPageState();
}

class _WorkerToolboxReturnPageState extends State<WorkerToolboxReturnPage> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = [];
  final Set<int> _selected = {};
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
      final list = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = list;
        _selected.removeWhere((id) => !list.any((r) => r['issue_id'] == id));
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

  Future<void> _submit() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      setState(() => _error = wT(
          en: 'Tap the tools you bring back.',
          ms: 'Tekan alat yang dipulangkan.',
          zh: '请先点选要归还的工具'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await PhotoCapture.takeEvidencePhoto();
      final r = await ApiService().toolboxReturn(
        issueIds: _selected.toList(),
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      toast(wT(
          en: '${r['returned_count'] ?? _selected.length} tools back',
          ms: '${r['returned_count'] ?? _selected.length} alat dipulang',
          zh: '已归还 ${r['returned_count'] ?? _selected.length} 件工具'));
      Navigator.of(context).pop(true);
    } on PhotoCaptureException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.cancelled
            ? null
            : wT(
                en: 'Camera did not open. Try again.',
                ms: 'Kamera tidak buka. Cuba lagi.',
                zh: '相机未打开，请再试一次');
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _apiError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
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

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((e) => (e['issue_id'] as num).toInt()));
      }
    });
  }

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
          wT(en: 'RETURN TOOLS', ms: 'PULANG ALAT', zh: '归还工具'),
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            iconSize: 28,
            color: AppColors.textSecondary,
            tooltip: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(children: [
          AppPageIntro(
            icon: Icons.assignment_return_rounded,
            enTitle: 'RETURN TOOLS',
            msTitle: 'PULANG ALAT',
            zhTitle: '归还工具',
            enSubtitle: 'Select tools and take a return photo',
            msSubtitle: 'Pilih alat dan ambil gambar',
            zhSubtitle: '选择工具并拍照归还',
            worker: true,
          ),
          const SizedBox(height: 14),
          Expanded(child: _body()),
            const SizedBox(height: 10),
            WBigAction(
              icon: Icons.photo_camera_rounded,
              label: wT(en: 'PHOTO & RETURN', ms: 'GAMBAR & PULANG', zh: '拍照归还'),
              color: AppColors.green,
              height: 96,
              busy: _busy,
              onTap: _items.isEmpty ? null : _submit,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: WErrorHint(
          title: wT(en: 'NO CONNECTION', ms: 'TIADA SAMBUNGAN', zh: '连接失败'),
          hint: _error!,
          onRetry: _load,
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: WEmpty(
          icon: Icons.inventory_2_rounded,
          title: wT(
              en: 'No tools out', ms: 'Tiada alat keluar', zh: '没有未归还的工具'),
          actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
          onAction: _load,
        ),
      );
    }

    return ListView(children: [
      WBigAction(
        icon: Icons.done_all_rounded,
        label: _selected.length == _items.length
            ? wT(en: 'CLEAR ALL', ms: 'KOSONGKAN', zh: '取消全选')
            : wT(en: 'SELECT ALL', ms: 'PILIH SEMUA', zh: '全选'),
        color: AppColors.green,
        height: kWPrimaryTap,
        outlined: true,
        onTap: _toggleAll,
      ),
      const SizedBox(height: 10),
      if (_error != null) ...[
        WErrorHint(
          title: wT(en: 'NOT SENT', ms: 'TIDAK DIHANTAR', zh: '未提交成功'),
          hint: _error!,
        ),
        const SizedBox(height: 10),
      ],
      for (final row in _items) ...[
        _issueRow(row),
        const SizedBox(height: 8),
      ],
    ]);
  }

  /// Whole row is the checkbox — a 24dp box is unusable with gloves on.
  Widget _issueRow(Map<String, dynamic> row) {
    final id = (row['issue_id'] as num).toInt();
    final picked = _selected.contains(id);
    final qty = (row['qty'] as num?)?.toInt() ?? 0;
    final color = picked ? AppColors.green : AppColors.textMuted;

    return Material(
      color: picked ? AppColors.greenLight : AppColors.bgCard,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: () => _toggle(id),
        child: Container(
          constraints: const BoxConstraints(minHeight: kWRowTap),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
                color: picked ? AppColors.green : AppColors.border,
                width: picked ? 2 : 1),
          ),
          child: Row(children: [
            Icon(
              picked ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 34,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (row['tool_name'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  if ((row['taken_at'] ?? '').toString().isNotEmpty)
                    Text(
                      _fmtDate(row['taken_at']),
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'x$qty',
              style: GoogleFonts.inter(
                  fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
          ]),
        ),
      ),
    );
  }

  String _fmtDate(Object? v) {
    final s = v.toString();
    if (s.length >= 16) return s.substring(0, 10);
    return s;
  }
}
