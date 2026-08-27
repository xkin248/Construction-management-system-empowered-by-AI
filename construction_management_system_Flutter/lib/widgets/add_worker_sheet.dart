import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../l10n/app_strings.dart';

/// Shared "Add Worker" bottom sheet.
///
/// Extracted from WorkersPage so that both the Workers page and the
/// Team Overview (Attendance) page can add workers through the same flow.
/// [onAdded] is invoked after a worker is successfully created / registered
/// so the caller can refresh its own list.
Future<void> showAddWorkerSheet(BuildContext context, {VoidCallback? onAdded}) {
  final name = TextEditingController();
  final role = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final pad = MediaQuery.of(ctx).viewInsets.bottom;
      return Container(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(AppStrings.t('workers.addWorker'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(controller: name,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.fullName'), hintText: AppStrings.t('workers.fullNameHint'))),
              const SizedBox(height: 12),
              TextField(controller: role,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.tradeRole'), hintText: AppStrings.t('workers.tradeRoleHint'))),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.phone'), hintText: AppStrings.t('workers.phoneHint'))),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.emailForLogin'), hintText: AppStrings.t('workers.emailHint'))),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: true,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.password'), hintText: AppStrings.t('workers.passwordHint'))),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) {
                    toast(AppStrings.t('workers.nameRequired'));
                    return;
                  }
                  try {
                    if (email.text.trim().isNotEmpty && password.text.isNotEmpty) {
                      // Register as authenticated worker (project auto-assigned by backend)
                      await ApiService().registerWorker(
                        name: name.text.trim(),
                        email: email.text.trim().toLowerCase(),
                        password: password.text,
                        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                        trade: role.text.trim().isEmpty ? null : role.text.trim(),
                      );
                    } else {
                      await ApiService().createWorker({
                        'name': name.text.trim(), 'trade': role.text.trim(),
                        'phone': phone.text.trim(),
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    toast(AppStrings.t('workers.added'));
                    onAdded?.call();
                  } on DioException catch (e) {
                    toast(e.message ?? AppStrings.t('common.failed'));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppStrings.t('workers.addWorker'),
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }),
  );
}
