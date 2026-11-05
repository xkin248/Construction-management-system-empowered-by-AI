import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../l10n/app_strings.dart';
import '../constants/trade_levels.dart';

/// Shared "Add Worker" bottom sheet.
///
/// Extracted from WorkersPage so that both the Workers page and the
/// Team Overview (Attendance) page can add workers through the same flow.
/// [onAdded] is invoked after a worker is successfully created / registered
/// so the caller can refresh its own list.
///
/// The trade field is a four-level picker ([TradeLevels.all]) instead of free
/// text: the backend now rejects anything that is not one of the four levels.
Future<void> showAddWorkerSheet(BuildContext context, {VoidCallback? onAdded}) {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  // Default to the lowest level so a supervisor never has to guess.
  String? level = TradeLevels.generalWorker;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final pad = MediaQuery.of(ctx).viewInsets.bottom;
      return Container(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + pad),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.bSheet,
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
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: AppRadius.rHair),
                ),
              ),
              Text(AppStrings.t('workers.addWorker'),
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(controller: name,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.fullName'), hintText: AppStrings.t('workers.fullNameHint'))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: level,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.t('workers.tradeRole'),
                  hintText: AppStrings.t('workers.tradeRoleHint'),
                ),
                items: TradeLevels.all
                    .map((l) => DropdownMenuItem(value: l.value, child: Text(l.label)))
                    .toList(),
                onChanged: (v) => setD(() => level = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.phone'), hintText: AppStrings.t('workers.phoneHint'))),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.emailForLogin'), hintText: AppStrings.t('workers.emailHint'))),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: true,
                  decoration: InputDecoration(labelText: AppStrings.t('workers.password'), hintText: AppStrings.t('workers.passwordHint'))),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) {
                    toast(AppStrings.t('workers.nameRequired'));
                    return;
                  }
                  if (level == null || level!.isEmpty) {
                    toast(AppStrings.t('worker.register.trade'));
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
                        trade: level,
                      );
                    } else {
                      await ApiService().createWorker({
                        'name': name.text.trim(), 'trade': level,
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
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
                child: Text(AppStrings.t('workers.addWorker'),
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }),
  );
}
