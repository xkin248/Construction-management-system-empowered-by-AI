import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/photo_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_common_task_card.dart';
import '../widgets/worker_ui.dart';

/// One daily job (morning briefing / toolbox talk / housekeeping).
///
/// The only way out of this page with the job closed is a photograph: the
/// camera opens first and the API is called only with the captured bytes, so a
/// worker can never tick the job off from the canteen. Everything else on the
/// screen is one icon, one word and one number.
class WorkerCommonTaskPage extends StatefulWidget {
  final int instanceId;
  final String kind;
  final String initialStatus;

  const WorkerCommonTaskPage({
    super.key,
    required this.instanceId,
    required this.kind,
    this.initialStatus = 'pending',
  });

  @override
  State<WorkerCommonTaskPage> createState() => _WorkerCommonTaskPageState();
}

class _WorkerCommonTaskPageState extends State<WorkerCommonTaskPage> {
  late String _status;
  String? _doneAt;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    AppSettings.lang.addListener(_rebuild);
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _done => _status == 'done';

  /// Camera first, API second — never the other way round.
  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await PhotoCapture.takeEvidencePhoto();
      final r = await ApiService().completeCommonTask(
        widget.instanceId,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
      );
      if (!mounted) return;
      setState(() {
        _status = (r['status'] ?? 'done').toString();
        _doneAt = _fmtTime(r['completed_at']);
        _busy = false;
      });
      toast(wT(en: 'Saved', ms: 'Disimpan', zh: '已提交'));
    } on PhotoCaptureException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // A cancelled camera is a choice, not an error: stay silent.
        _error = e.cancelled
            ? null
            : wT(
                en: 'Camera did not open. Try again.',
                ms: 'Kamera tidak buka. Cuba lagi.',
                zh: '相机未打开，请再试一次',
              );
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

  String? _fmtTime(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 16) return s.substring(11, 16);
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final color = _done ? AppColors.green : AppColors.accent;
    final title = wCommonTaskTitle(widget.kind);

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: Text(
          title,
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(children: [
            Expanded(
              child: ListView(children: [
                _statusBlock(color),
                const SizedBox(height: 14),
                _ruleBox(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  WErrorHint(
                    title: wT(en: 'NOT SAVED', ms: 'TIDAK SIMPAN', zh: '未提交成功'),
                    hint: _error!,
                    onRetry: _busy ? null : _submit,
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            WBigAction(
              icon: Icons.photo_camera_rounded,
              label: _done
                  ? wT(en: 'NEW PHOTO', ms: 'GAMBAR BARU', zh: '重新拍照')
                  : wT(en: 'TAKE PHOTO', ms: 'AMBIL GAMBAR', zh: '拍照提交'),
              color: _done ? AppColors.textSecondary : AppColors.accent,
              outlined: _done,
              height: 96,
              busy: _busy,
              onTap: _submit,
            ),
          ]),
        ),
      ),
    );
  }

  /// Status = one huge icon + one word (+ the time it was closed, if any).
  Widget _statusBlock(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: _done ? color : AppColors.border, width: _done ? 2 : 1),
      ),
      child: Column(children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _done ? Icons.check_rounded : wCommonTaskIcon(widget.kind),
            size: 56,
            color: color,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _done
              ? wT(en: 'DONE', ms: 'SIAP', zh: '已完成')
              : wT(en: 'NOT DONE', ms: 'BELUM', zh: '待完成'),
          style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w900, color: color),
        ),
        if (_doneAt != null) ...[
          const SizedBox(height: 8),
          WChip(icon: Icons.schedule_rounded, label: _doneAt!, color: AppColors.blue),
        ],
      ]),
    );
  }

  /// One sentence: the photo is not optional.
  Widget _ruleBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentLight,
        borderRadius: AppRadius.rMd,
      ),
      child: Row(children: [
        Icon(Icons.info_rounded, size: 28, color: AppColors.accentText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            wT(
              en: 'A photo is needed to finish. Camera only.',
              ms: 'Gambar wajib untuk siap. Kamera sahaja.',
              zh: '必须拍照才能完成，仅限相机',
            ),
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.3),
          ),
        ),
      ]),
    );
  }
}
