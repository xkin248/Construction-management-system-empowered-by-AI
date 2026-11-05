import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/photo_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_ui.dart';

/// Toolbox — take tools out.
///
/// Several tools go out under ONE photo of the tray (the backend models it the
/// same way), so the worker fills a short list, adds the quantity with big +/-
/// pads, and then takes a single photo. No dropdowns, no keyboard-only fields.
class WorkerToolboxTakePage extends StatefulWidget {
  /// Today's `toolbox` common-task instance, so taking the tools can also close
  /// the daily checklist item with the very same photo (no second shot).
  final int? dailyInstanceId;
  final bool dailyDone;

  const WorkerToolboxTakePage({
    super.key,
    this.dailyInstanceId,
    this.dailyDone = false,
  });

  @override
  State<WorkerToolboxTakePage> createState() => _WorkerToolboxTakePageState();
}

class _ToolLine {
  _ToolLine(this.key);
  final int key;
  final TextEditingController name = TextEditingController();
  int qty = 1;

  void dispose() => name.dispose();
}

class _WorkerToolboxTakePageState extends State<WorkerToolboxTakePage> {
  final List<_ToolLine> _lines = [];
  int _nextKey = 1;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppSettings.lang.addListener(_rebuild);
    _addLine();
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_rebuild);
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _addLine() {
    if (_lines.length >= 20) {
      toast(wT(en: 'Maximum 20 tools', ms: 'Maksimum 20 alat', zh: '最多 20 件工具'));
      return;
    }
    setState(() => _lines.add(_ToolLine(_nextKey++)));
  }

  void _removeLine(_ToolLine line) {
    if (_lines.length <= 1) return;
    setState(() => _lines.remove(line));
    line.dispose();
  }

  /// Only lines with a real name are sent; the server rejects empty names, and
  /// an untouched extra row should not block the worker.
  List<Map<String, dynamic>> _items() {
    final out = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final name = l.name.text.trim();
      if (name.isEmpty) continue;
      out.add({'tool_name': name, 'qty': l.qty.clamp(1, 100)});
    }
    return out;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final items = _items();
    if (items.isEmpty) {
      setState(() => _error = wT(
          en: 'Add one tool name first.',
          ms: 'Isi satu nama alat dahulu.',
          zh: '请先填写一件工具名称'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await PhotoCapture.takeEvidencePhoto();
      final r = await ApiService().toolboxTake(
        items: items,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
      );
      // The tray photo doubles as the daily toolbox-talk evidence.
      await _closeDailyTask(photo);
      if (!mounted) return;
      setState(() => _busy = false);
      toast(wT(
          en: '${r['count'] ?? items.length} tools recorded',
          ms: '${r['count'] ?? items.length} alat direkod',
          zh: '已登记 ${r['count'] ?? items.length} 件工具'));
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

  /// Best effort: the tools are already signed out at this point, so a failure
  /// here must never turn a successful hand-over into an error screen.
  Future<void> _closeDailyTask(CapturedPhoto photo) async {
    final id = widget.dailyInstanceId;
    if (id == null || widget.dailyDone) return;
    try {
      await ApiService().completeCommonTask(
        id,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
      );
    } catch (_) {
      // Left as "not done"; the worker can still finish it from the home card.
    }
  }

  String _apiError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is String && data.isNotEmpty) return data;
    return e.message ?? 'Request failed';
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
          wT(en: 'TAKE TOOLS', ms: 'AMBIL ALAT', zh: '领取工具'),
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(children: [
            Expanded(
              child: ListView(
                children: [
                  for (final line in _lines) ...[
                    _lineCard(line),
                    const SizedBox(height: 10),
                  ],
                  WBigAction(
                    icon: Icons.add_rounded,
                    label: wT(en: 'ADD TOOL', ms: 'TAMBAH ALAT', zh: '加一件工具'),
                    color: AppColors.accent,
                    height: kWPrimaryTap,
                    outlined: true,
                    onTap: _addLine,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    WErrorHint(
                      title: wT(en: 'CHECK AGAIN', ms: 'SEMAK SEMULA', zh: '请再检查'),
                      hint: _error!,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    wT(
                      en: 'One photo of all the tools.',
                      ms: 'Satu gambar untuk semua alat.',
                      zh: '所有工具拍一张照片即可',
                    ),
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            WBigAction(
              icon: Icons.photo_camera_rounded,
              label: wT(en: 'PHOTO & TAKE', ms: 'GAMBAR & AMBIL', zh: '拍照领取'),
              color: AppColors.accent,
              height: 96,
              busy: _busy,
              onTap: _submit,
            ),
          ]),
        ),
      ),
    );
  }

  /// One tool = a name field plus a big quantity stepper.
  Widget _lineCard(_ToolLine line) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: line.name,
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                isDense: true,
                hintText: wT(en: 'Tool name', ms: 'Nama alat', zh: '工具名称'),
                hintStyle: GoogleFonts.inter(
                    fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                prefixIcon: Icon(Icons.handyman_rounded, size: 26, color: AppColors.accent),
                border: OutlineInputBorder(borderRadius: AppRadius.rMd),
              ),
            ),
          ),
          if (_lines.length > 1)
            IconButton(
              iconSize: 28,
              color: AppColors.red,
              tooltip: wT(en: 'Remove', ms: 'Buang', zh: '删除'),
              onPressed: () => _removeLine(line),
              icon: const Icon(Icons.close_rounded),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _qtyButton(Icons.remove_rounded, () {
            if (line.qty > 1) setState(() => line.qty--);
          }),
          Expanded(
            child: Center(
              child: Text(
                '${line.qty}',
                style: GoogleFonts.inter(
                    fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ),
          ),
          _qtyButton(Icons.add_rounded, () {
            if (line.qty < 100) setState(() => line.qty++);
          }),
        ]),
      ]),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.accentLight,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 60,
          child: Icon(icon, size: 32, color: AppColors.accentText),
        ),
      ),
    );
  }
}
