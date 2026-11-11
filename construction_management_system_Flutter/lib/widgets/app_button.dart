import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../theme/app_theme.dart';

/// Shared button vocabulary for the BuildSmart rebuild
/// (BuildSmart_Button_Click_UI_Specification.md §2 "Button behaviour",
/// §3 "Common visual style", PART C §20 "Common dialogs and messages").
///
/// Every button built from this file gets the four behaviours the spec asks for:
///  1. exactly one clear label,
///  2. a loading state that replaces the label (`Saving…`, `Logging in…`),
///  3. no repeat submit while busy (`onPressed` becomes null),
///  4. a readable failure message — success is only ever announced by the caller
///     *after* the backend confirms the action.
enum AppButtonTone {
  /// Orange solid fill — the one primary action on a screen.
  primary,

  /// White fill with a hairline border — Cancel / Back / secondary actions.
  secondary,

  /// Red fill — delete / deactivate. Always pair with [confirmDestructive].
  destructive,
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = AppButtonTone.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = true,
    this.height = 48,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonTone tone;
  final IconData? icon;

  /// While true the button shows a spinner + [loadingLabel] and ignores taps.
  final bool loading;

  /// Shown in place of [label] while [loading] (e.g. `Saving…`).
  final String? loadingLabel;

  final bool expand;
  final double height;
  final IconData? trailingIcon;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final BorderSide side;

    switch (tone) {
      case AppButtonTone.primary:
        bg = _enabled || loading ? AppColors.accentSolid : AppColors.accentSolid.withValues(alpha: 0.4);
        fg = AppColors.onAccent;
        side = BorderSide.none;
      case AppButtonTone.secondary:
        bg = AppColors.bgCard;
        fg = AppColors.textPrimary;
        side = BorderSide(color: AppColors.border, width: 1.4);
      case AppButtonTone.destructive:
        bg = _enabled || loading ? AppColors.danger : AppColors.danger.withValues(alpha: 0.4);
        fg = AppColors.onAccent;
        side = BorderSide.none;
    }

    final content = SizedBox(
      height: height,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            )
          else if (icon != null)
            Icon(icon, size: 19, color: fg),
          if (loading || icon != null) const SizedBox(width: 8),
          Flexible(
            child: Text(
              loading ? (loadingLabel ?? label) : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (trailingIcon != null && !loading) ...[
            const SizedBox(width: 6),
            Icon(trailingIcon, size: 18, color: fg),
          ],
        ],
      ),
    );

    return Material(
      color: bg,
      borderRadius: AppRadius.rBtn,
      child: InkWell(
        borderRadius: AppRadius.rBtn,
        onTap: _enabled ? onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rBtn,
            border: side == BorderSide.none ? null : Border.fromBorderSide(side),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Spec PART C §20 "Delete action": the dialog must name the record being
/// removed. Nothing destructive runs before this returns true.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String? recordName,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rSheet),
      title: Text(
        title,
        style: GoogleFonts.inter(
            fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recordName != null && recordName.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgMain,
                borderRadius: AppRadius.rMd,
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                recordName,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            style: GoogleFonts.inter(
                fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AppSettings.t(
                  'This action cannot be undone.',
                  '此操作不可撤销。',
                  'Tindakan ini tidak boleh dibatalkan.',
                ),
                style: GoogleFonts.inter(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger),
              ),
            ),
          ]),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        Row(children: [
          Expanded(
            child: AppButton(
              label: AppSettings.t('Cancel', '取消', 'Batal'),
              tone: AppButtonTone.secondary,
              height: 46,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              label: confirmLabel,
              tone: AppButtonTone.destructive,
              height: 46,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ),
        ]),
      ],
    ),
  );
  return ok ?? false;
}

/// One readable sentence for any failure, never a raw stack trace or a raw
/// HTTP body. Login failures deliberately do NOT reveal whether the email
/// exists (spec §4 error states).
String readableError(Object error, {String? fallback}) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    final serverMsg = _serverDetail(error);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return AppSettings.t(
          'Unable to connect. Check your internet and try again.',
          '无法连接，请检查网络后重试。',
          'Tidak dapat menyambung. Semak internet dan cuba lagi.',
        );
      case DioExceptionType.badCertificate:
        return AppSettings.t(
          'Secure connection failed. Try another network.',
          '安全连接失败，请更换网络。',
          'Sambungan selamat gagal. Cuba rangkaian lain.',
        );
      case DioExceptionType.cancel:
        return AppSettings.t('Request cancelled.', '请求已取消。', 'Permintaan dibatalkan.');
      case DioExceptionType.badResponse:
        if (code == 401 || code == 400) {
          return AppSettings.t(
            'Incorrect email / Worker ID or password.',
            '邮箱/工号或密码不正确。',
            'E-mel / ID pekerja atau kata laluan salah.',
          );
        }
        if (code == 403) {
          return AppSettings.t(
            'This account is disabled or has no access. Contact your supervisor.',
            '该账号已停用或无权限，请联系监理。',
            'Akaun ini dinyahdayakan atau tiada akses. Hubungi penyelia anda.',
          );
        }
        if (code == 404) {
          return AppSettings.t(
            'Record not found. Refresh and try again.',
            '记录不存在，请刷新后重试。',
            'Rekod tidak dijumpai. Muat semula dan cuba lagi.',
          );
        }
        if (code != null && code >= 500) {
          return AppSettings.t(
            'Server problem. Try again in a moment.',
            '服务器异常，请稍后再试。',
            'Masalah pelayan. Cuba sebentar lagi.',
          );
        }
        return serverMsg ??
            AppSettings.t('Request failed.', '请求失败。', 'Permintaan gagal.');
      default:
        return AppSettings.t(
          'Unable to connect. Check your internet and try again.',
          '无法连接，请检查网络后重试。',
          'Tidak dapat menyambung. Semak internet dan cuba lagi.',
        );
    }
  }
  return fallback ??
      AppSettings.t('Something went wrong. Try again.', '出错了，请重试。', 'Ada masalah. Cuba lagi.');
}

String? _serverDetail(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final d = data['detail'] ?? data['message'];
    if (d is String && d.trim().isNotEmpty) return d.trim();
    if (d is List && d.isNotEmpty) {
      final first = d.first;
      if (first is Map && first['msg'] != null) return first['msg'].toString();
      return first.toString();
    }
  }
  return null;
}

/// Inline, dismissible error block (never a snackbar for a blocking failure —
/// the spec wants the reason to stay on screen next to the action that failed).
class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({super.key, required this.message, this.onRetry, this.retryLabel});

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.redLight,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.inter(
                fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              retryLabel ?? AppSettings.t('Retry', '重试', 'Cuba'),
              style: GoogleFonts.inter(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.danger),
            ),
          ),
      ]),
    );
  }
}
