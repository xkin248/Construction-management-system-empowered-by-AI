import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_settings_actions.dart';
import '../widgets/worker_ui.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'worker_dashboard_page.dart';
import 'worker_tasks_page.dart';

/// Worker shell — three tabs only.
///
/// The old shell carried five tabs (home / tasks / attendance / alerts /
/// profile). Attendance and alerts were second homes for information that a
/// low-literacy worker never reads: the shared worker sees three big targets
/// now, and every secondary screen opens from a big button on those three.
const int kWorkerTabHome = 0;
const int kWorkerTabTasks = 1;
const int kWorkerTabProfile = 2;

class WorkerHomeShell extends StatefulWidget {
  const WorkerHomeShell({super.key});
  @override
  State<WorkerHomeShell> createState() => _WorkerHomeShellState();
}

class _WorkerHomeShellState extends State<WorkerHomeShell> {
  int idx = kWorkerTabHome;

  @override
  void initState() {
    super.initState();
    // Labels are resolved inside build(), so the shell must rebuild when the
    // language or the theme changes.
    AppSettings.lang.addListener(_onSettingsChanged);
    AppColors.darkMode.addListener(_onSettingsChanged);
    _bootstrapLanguage();
  }

  /// Workers default to Bahasa Melayu on the first launch of the worker area.
  /// The flag is stored so an explicit choice made later in Settings is kept.
  Future<void> _bootstrapLanguage() async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('worker_lang_ready') == true) return;
    await sp.setBool('worker_lang_ready', true);
    if (!mounted) return;
    if (AppSettings.lang.value != 'ms') AppSettings.lang.value = 'ms';
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

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    ApiService().ct();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  void _go(int i, [int subTab = 0]) {
    setState(() => idx = i);
  }

  List<Widget> _buildPages() => [
        WorkerDashboardPage(onNavigate: _go),
        const WorkerTasksPage(),
        const ProfilePage(),
      ];

  Future<void> _openAlerts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
  }

  String get _title {
    switch (idx) {
      case kWorkerTabTasks:
        return wT(en: 'MY TASKS', ms: 'TUGASAN', zh: '我的任务');
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
        title: Text(_title,
            style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            iconSize: 28,
            icon: Icon(Icons.notifications_rounded, color: AppColors.textSecondary),
            tooltip: wT(en: 'ALERTS', ms: 'AMARAN', zh: '通知'),
            onPressed: _openAlerts,
          ),
          const AppSettingsActions(),
          IconButton(
            iconSize: 28,
            icon: Icon(Icons.power_settings_new_rounded, color: AppColors.red),
            tooltip: wT(en: 'LOG OUT', ms: 'KELUAR', zh: '退出登录'),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(index: idx, children: _buildPages()),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            _navItem(kWorkerTabHome, Icons.home_rounded,
                wT(en: 'HOME', ms: 'UTAMA', zh: '首页')),
            _navItem(kWorkerTabTasks, Icons.checklist_rounded,
                wT(en: 'TASKS', ms: 'TUGASAN', zh: '任务')),
            _navItem(kWorkerTabProfile, Icons.person_rounded,
                wT(en: 'ME', ms: 'SAYA', zh: '我的')),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = idx == index;
    final color = active ? AppColors.accent : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: () => _go(index),
        child: SizedBox(
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: color),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
