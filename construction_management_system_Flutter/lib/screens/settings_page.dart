import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Column(children: [
      Container(
        color: AppColors.bgCard,
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [Tab(text: 'General'), Tab(text: 'Notifications'), Tab(text: 'Geofence'), Tab(text: 'Users & Roles')],
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: const [_GeneralTab(), _NotificationsTab(), _GeofenceTab(), _UsersTab()]),
      ),
    ]);
  }
}

// ========== General ==========
class _GeneralTab extends StatefulWidget {
  const _GeneralTab();
  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> {
  bool ld = true;
  final company = TextEditingController(), tz = TextEditingController(), dateFmt = TextEditingController();
  final workStart = TextEditingController(), workEnd = TextEditingController(), lateThreshold = TextEditingController();
  String language = 'English';
  Map settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      settings = await ApiService().getSettings();
      company.text = settings['company_name'] ?? '';
      tz.text = settings['timezone'] ?? '';
      dateFmt.text = settings['date_format'] ?? '';
      workStart.text = settings['work_start'] ?? '';
      workEnd.text = settings['work_end'] ?? '';
      lateThreshold.text = settings['late_threshold'] ?? '';
      language = settings['system_language'] ?? 'English';
    } catch (e) {
      toast('Failed to load settings: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _save() async {
    try {
      await ApiService().updateSettings({
        ...settings,
        'company_name': company.text, 'system_language': language, 'timezone': tz.text, 'date_format': dateFmt.text,
        'work_start': workStart.text, 'work_end': workEnd.text, 'late_threshold': lateThreshold.text,
      });
      toast('✅ Settings saved');
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to save settings');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      sectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('General Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 14),
          TextField(controller: company, decoration: const InputDecoration(labelText: 'Company Name')),
          const SizedBox(height: 12),
          TextField(controller: tz, decoration: const InputDecoration(labelText: 'Timezone')),
          const SizedBox(height: 12),
          TextField(controller: dateFmt, decoration: const InputDecoration(labelText: 'Date Format')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: workStart, decoration: const InputDecoration(labelText: 'Work Start'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: workEnd, decoration: const InputDecoration(labelText: 'Work End'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: lateThreshold, decoration: const InputDecoration(labelText: 'Late Threshold', helperText: 'Workers checking in after this time are marked Late')),
          const SizedBox(height: 18),
          ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save Changes')),
        ]),
      ),
    ]);
  }
}

// ========== Notifications ==========
class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab();
  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  bool ld = true;
  Map settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      settings = await ApiService().getSettings();
    } catch (e) {
      toast('Failed to load settings: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _toggle(String key, bool v) async {
    setState(() => settings[key] = v);
    try {
      await ApiService().updateSettings(settings);
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to save');
    }
  }

  Widget _row(String key, String title, String sub) => sectionCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ]),
          ),
          Switch(value: settings[key] == true, activeThumbColor: AppColors.accent, onChanged: (v) => _toggle(key, v)),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      _row('notif_attendance', 'Attendance Alerts', 'Notify when workers are absent or late'),
      _row('notif_task_overdue', 'Task Overdue', 'Alert when tasks pass their due date'),
      _row('notif_budget', 'Budget Warnings', 'Warn when project spending exceeds 80%'),
      _row('notif_safety', 'Safety Incidents', 'Immediate alert on safety events'),
      _row('notif_daily_summary', 'Daily Summary', 'Send daily project summary report'),
      _row('notif_weekly_report', 'Weekly Report', 'Send weekly analytics report'),
    ]);
  }
}

// ========== Geofence ==========
class _GeofenceTab extends StatefulWidget {
  const _GeofenceTab();
  @override
  State<_GeofenceTab> createState() => _GeofenceTabState();
}

class _GeofenceTabState extends State<_GeofenceTab> {
  bool ld = true;
  List projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
    } catch (e) {
      toast('Failed to load projects: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _updateRadius(Map p, double radius) async {
    try {
      await ApiService().updateProject(p['project_id'], {
        'project_name': p['project_name'], 'location_address': p['location_address'],
        'start_date': p['start_date'], 'end_date': p['end_date'], 'status': p['status'], 'progress': p['progress'],
        'center_lat': p['center_lat'], 'center_lng': p['center_lng'], 'fence_radius': radius,
      });
      toast('✅ Geofence updated');
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to update geofence');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      sectionCard(
        margin: const EdgeInsets.only(bottom: 14),
        child: const Row(children: [
          Icon(Icons.location_on_outlined, size: 16, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text('GPS geofencing automatically records attendance when workers enter or exit designated site boundaries.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        ]),
      ),
      ...projects.map((p) {
        final ctrl = TextEditingController(text: (p['fence_radius'] ?? 500).toStringAsFixed(0));
        return sectionCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['project_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const Text('Geofence radius', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ]),
            ),
            SizedBox(
              width: 70,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(isDense: true, suffixText: 'm'),
                onSubmitted: (v) { final r = double.tryParse(v); if (r != null) _updateRadius(p, r); },
              ),
            ),
            const SizedBox(width: 8),
            statusPill('active'),
          ]),
        );
      }),
    ]);
  }
}

// ========== Users & Roles ==========
class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  bool ld = true;
  List users = [];
  static const _roles = ['project_manager', 'site_supervisor', 'worker'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      users = await ApiService().getUsers();
    } catch (e) {
      toast('Failed to load users: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  void _openInvite() {
    final name = TextEditingController(), email = TextEditingController(), pwd = TextEditingController();
    String role = 'site_supervisor';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Invite User'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setD(() => role = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary Password')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || email.text.trim().isEmpty || pwd.text.length < 6) {
                  toast('Please fill all fields (password min. 6 characters)');
                  return;
                }
                try {
                  await ApiService().inviteUser({'full_name': name.text.trim(), 'email': email.text.trim(), 'role': role, 'password': pwd.text});
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('✅ User invited');
                  _load();
                } on DioException catch (e) {
                  toast(e.message ?? 'Failed to invite user');
                }
              },
              child: const Text('Invite'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _changeRole(Map u) async {
    String role = u['role'] ?? 'site_supervisor';
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change role for ${u['full_name']}'),
        content: StatefulBuilder(
          builder: (ctx, setD) => Column(
            mainAxisSize: MainAxisSize.min,
            children: _roles.map((r) => RadioListTile<String>(
                  // ignore: deprecated_member_use
                  value: r, groupValue: role, title: Text(r.replaceAll('_', ' ')),
                  // ignore: deprecated_member_use
                  onChanged: (v) => setD(() => role = v!),
                )).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, role), child: const Text('Save')),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await ApiService().updateUserRole(u['supervisor_id'], picked);
      toast('✅ Role updated');
      _load();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to update role');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _openInvite, icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Invite User')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        ...users.map((u) => sectionCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                initialsAvatar(u['full_name'] ?? '?', radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u['full_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(u['email'] ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  ]),
                ),
                statusPill(u['role'] ?? 'site_supervisor', label: (u['role'] ?? '').toString().replaceAll('_', ' ')),
                IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _changeRole(u)),
              ]),
            )),
      ]),
    );
  }
}
