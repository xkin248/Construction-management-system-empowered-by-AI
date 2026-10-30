import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// What kind of failure the user is looking at.
///
/// The distinction matters on site: "no internet / slow site network" needs a
/// different next action than "the server broke". Everything is derived from the
/// thrown object, so pages only have to pass the raw error.
enum FailureKind { offline, timeout, server, unknown }

extension FailureKindLabels on FailureKind {
  String get titleKey => switch (this) {
        FailureKind.offline => 'fail.offline.title',
        FailureKind.timeout => 'fail.timeout.title',
        FailureKind.server => 'fail.server.title',
        FailureKind.unknown => 'fail.unknown.title',
      };

  String get descriptionKey => switch (this) {
        FailureKind.offline => 'fail.offline.desc',
        FailureKind.timeout => 'fail.timeout.desc',
        FailureKind.server => 'fail.server.desc',
        FailureKind.unknown => 'fail.unknown.desc',
      };

  IconData get icon => switch (this) {
        FailureKind.offline => Icons.wifi_off_rounded,
        FailureKind.timeout => Icons.timer_off_rounded,
        FailureKind.server => Icons.dns_rounded,
        FailureKind.unknown => Icons.error_outline_rounded,
      };

  Color get accent => switch (this) {
        FailureKind.offline => AppColors.warning,
        FailureKind.timeout => AppColors.info,
        FailureKind.server => AppColors.danger,
        FailureKind.unknown => AppColors.textMuted,
      };

  Color get plate => switch (this) {
        FailureKind.offline => AppColors.yellowLight,
        FailureKind.timeout => AppColors.blueLight,
        FailureKind.server => AppColors.redLight,
        FailureKind.unknown => AppColors.borderLight,
      };
}

/// Classifies any thrown object into a user-facing failure kind.
///
/// Deliberately avoids `dart:io` so the same code compiles for Flutter web.
FailureKind failureKindOf(Object? error) {
  if (error == null) return FailureKind.unknown;

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return FailureKind.timeout;
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return FailureKind.offline;
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode ?? 0;
        if (code == 408 || code == 504) return FailureKind.timeout;
        return FailureKind.server;
      case DioExceptionType.cancel:
        return FailureKind.unknown;
      case DioExceptionType.unknown:
        return failureKindOf(error.error);
      default:
        // Forward-compatible: newer dio versions may add enum values.
        return FailureKind.unknown;
    }
  }

  if (error is TimeoutException) return FailureKind.timeout;

  final s = error.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('network is unreachable') ||
      s.contains('networkerror') ||
      s.contains('connection error') ||
      s.contains('xmlhttprequest error') ||
      s.contains('clientexception')) {
    return FailureKind.offline;
  }
  if (s.contains('timeout') || s.contains('timed out')) {
    return FailureKind.timeout;
  }
  if (s.contains('status code of') ||
      s.contains('statuscode') ||
      s.contains('internal server error') ||
      RegExp(r'\b5\d\d\b').hasMatch(s)) {
    return FailureKind.server;
  }
  return FailureKind.unknown;
}

/// Standard failure state: icon + one-line reason + retry button.
///
/// Always offers a way forward (retry) instead of the silent blank screens the
/// app used to show after a failed fetch.
class FailureState extends StatelessWidget {
  const FailureState({
    super.key,
    this.error,
    this.kind,
    this.icon,
    this.title,
    this.description,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
    this.padding = const EdgeInsets.all(24),
  });

  /// Raw thrown object; used to derive the kind when [kind] is null.
  final Object? error;

  /// Explicit kind (overrides classification of [error]).
  final FailureKind? kind;
  final IconData? icon;

  /// Overrides the kind-based title / one-line reason.
  final String? title;
  final String? description;

  final VoidCallback? onRetry;
  final String? retryLabel;
  final bool compact;
  final EdgeInsetsGeometry padding;

  FailureKind get _kind => kind ?? failureKindOf(error);

  @override
  Widget build(BuildContext context) {
    final k = _kind;
    final plateSize = compact ? 56.0 : 76.0;

    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: plateSize,
                height: plateSize,
                decoration: BoxDecoration(color: k.plate, shape: BoxShape.circle),
                child: Icon(icon ?? k.icon, size: compact ? 24 : 32, color: k.accent),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title ?? AppStrings.t(k.titleKey),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description ?? AppStrings.t(k.descriptionKey),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: compact ? 12.5 : 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel ?? AppStrings.t('common.retry')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
                    textStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline failure strip for a single card/section that failed while the
/// rest of the page still has data (e.g. one dashboard endpoint out of four).
class FailureInline extends StatelessWidget {
  const FailureInline({
    super.key,
    this.error,
    this.kind,
    this.message,
    this.onRetry,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 30),
  });

  final Object? error;
  final FailureKind? kind;
  final String? message;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final k = kind ?? failureKindOf(error);
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FailureState(
            kind: k,
            icon: k.icon,
            description: message,
            onRetry: onRetry,
            compact: true,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
