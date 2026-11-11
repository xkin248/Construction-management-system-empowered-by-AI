import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_settings_actions.dart';
import '../widgets/worker_ui.dart';
import 'worker_dashboard_page.dart';
import 'worker_notifications_page.dart';
import 'worker_profile_page.dart';
import 'worker_tasks_page.dart';

/// Worker shell â€” the five-tab bar from the current UI reference:
/// Home / Tasks / Attendance / Safety / Profile.
///
/// The notification bell lives in the top bar (not in the tab bar) exactly as
/// the reference draws it; Account settings stay one tap away in the same bar,
/// while log out moved into Profile so the bar keeps only what the drawing has.
const int kWorkerTabHome = 0;
const int kWorkerTabTasks = 1;
// Kept as sentinel values while old deep-links are retired. They are not
// rendered: attendance now belongs to Home and safety belongs to Tasks.
const int kWorkerTabAttendance = -1;
const int kWorkerTabSafety = -2;
const int kWorkerTabProfile = 2;

class WorkerHomeShell extends StatefulWidget {
  const WorkerHomeShell({super.key});
  @override
  State<WorkerHomeShell> createState() => _WorkerHomeShellState();
}

class _WorkerHomeShellState extends State<WorkerHomeShell> {
  int idx = kWorkerTabHome;
  bool get _showLegacyTabs => false;

  @override
  void initState() {
    super.initState();
    // Labels are resolved inside build(), so the shell must rebuild when the
    // language or the theme changes.
    AppSettings.lang.addListener(_onSettingsChanged);
    AppColors.darkMode.addListener(_onSettingsChanged);
    _bootstrapLanguage();
  }

  /// English is the first-run language for every role. The one-time marker
  /// also upgrades devices that previously received the old BM worker default;
  /// a language explicitly selected afterwards remains unchanged.
  Future<void> _bootstrapLanguage() async {
    final sp = await SharedPreferences.getInstance();
    const marker = 'worker_english_default_v1';
    if (sp.getBool(marker) == true) return;
    await sp.setBool(marker, true);
    if (!mounted) return;
    if (AppSettings.lang.value != 'en') AppSettings.lang.value = 'en';
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_onSettingsChanged);
    AppColors.darkMode.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _go(int i) {
    setState(() => idx = i);
  }

  List<Widget> _buildPages() => const [
        WorkerDashboardPage(),
        WorkerTasksPage(),
        WorkerProfilePage(),
      ];

  Future<void> _openAlerts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkerNotificationsPage()),
    );
  }

  String get _title {
    switch (idx) {
      case kWorkerTabTasks:
        return wT(en: 'MY TASKS', ms: 'TUGASAN', zh: '我的任务');
      case kWorkerTabAttendance:
        return wT(en: 'ATTENDANCE', ms: 'KEDATANGAN', zh: '考勤');
      case kWorkerTabSafety:
        return wT(en: 'SAFETY', ms: 'KESELAMATAN', zh: '安全');
      case kWorkerTabProfile:
        return wT(en: 'ME', ms: 'SAYA', zh: '我的');
      default:
        return 'BuildSmart';
    }
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        titleSpacing: 16,
        title: Row(children: [
          if (idx == kWorkerTabHome) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.architecture_rounded, size: 16, color: AppColors.onAccent),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ]),
        actions: [
          Stack(children: [
            IconButton(
              iconSize: 26,
              icon: Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary),
              tooltip: wT(en: 'ALERTS', ms: 'AMARAN', zh: '通知'),
              onPressed: _openAlerts,
            ),
            // Deliberately no unread dot: do not imply an unread count
            // without a response from the notification endpoint.
          ]),
          const AppSettingsActions(),
        ],
      ),
      body: IndexedStack(index: idx, children: _buildPages()),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            border: Border(top: BorderSide(color: AppColors.border)),
            boxShadow: AppShadows.sm,
          ),
          child: Row(children: [
            _navItem(kWorkerTabHome, Icons.home_rounded,
                wT(en: 'HOME', ms: 'UTAMA', zh: '首页')),
            _navItem(kWorkerTabTasks, Icons.assignment_rounded,
                wT(en: 'TASKS', ms: 'TUGASAN', zh: '任务')),
            if (_showLegacyTabs) _navItem(kWorkerTabAttendance, Icons.fingerprint_rounded,
                wT(en: 'ATTEND', ms: 'HADIR', zh: '考勤')),
            if (_showLegacyTabs) _navItem(kWorkerTabSafety, Icons.health_and_safety_rounded,
                wT(en: 'SAFETY', ms: 'SELAMAT', zh: '安全')),
            _navItem(kWorkerTabProfile, Icons.person_rounded,
                wT(en: 'ME', ms: 'SAYA', zh: '我的')),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = idx == index;
    return Expanded(
      child: InkWell(
        onTap: () => _go(index),
        child: SizedBox(
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: active ? AppColors.accentLight : AppColors.transparent,
                  borderRadius: AppRadius.rPill,
                ),
                child: Icon(icon,
                    size: 23, color: active ? AppColors.accentText : AppColors.textMuted),
              ),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                      color: active ? AppColors.accentText : AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
