import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map? user;
  bool ld = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      user = await ApiService().me();
    } catch (e) {
      toast('Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    ApiService().ct();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('My Profile'),
      ),
      body: ld
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              sectionCard(
                child: Column(children: [
                  initialsAvatar(user?['full_name'] ?? '?', radius: 34),
                  const SizedBox(height: 12),
                  Text(user?['full_name'] ?? '-', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(user?['email'] ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  const SizedBox(height: 8),
                  statusPill(user?['role'] ?? 'site_supervisor', label: (user?['role'] ?? '').toString().replaceAll('_', ' ')),
                ]),
              ),
              const SizedBox(height: 16),
              sectionCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.phone_outlined, color: AppColors.textSecondary),
                    title: const Text('Phone'),
                    trailing: Text(user?['phone'] ?? '-', style: const TextStyle(color: AppColors.textMuted)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                    title: const Text('App Settings'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => toast('Use the Settings section from the menu'),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
                label: const Text('Log Out', style: TextStyle(color: AppColors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.redLight), minimumSize: const Size.fromHeight(46)),
              ),
            ]),
    );
  }
}
