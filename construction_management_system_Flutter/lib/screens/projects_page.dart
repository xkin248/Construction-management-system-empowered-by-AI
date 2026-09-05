import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../services/gps_notification_service.dart';
import '../l10n/app_strings.dart';
import '../utils/date_helper.dart';
import '../widgets/task_form.dart';
import 'tasks_page.dart' show TaskDetailPage;

// ─────────────────────────────────────────────
//  Fence Map (OpenStreetMap free tiles) — center marker + radius circle
// ─────────────────────────────────────────────
class _FenceMap extends StatelessWidget {
  final double lat;
  final double lng;
  final double radiusMeters;
  final void Function(LatLng point)? onTap;
  final double height;

  const _FenceMap({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.onTap,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final center = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            onTap: onTap == null ? null : (tapPos, latLng) => onTap!(latLng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.buildsmart.app',
            ),
            CircleLayer(circles: [
              CircleMarker(
                point: center,
                radius: radiusMeters <= 0 ? 5000 : radiusMeters,
                useRadiusInMeter: true,
                color: AppColors.accent.withValues(alpha: 0.15),
                borderColor: AppColors.accent,
                borderStrokeWidth: 2,
              ),
            ]),
            MarkerLayer(markers: [
              Marker(
                point: center,
                width: 42,
                height: 42,
                child: Icon(Icons.location_on_rounded, color: AppColors.red, size: 38),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  GPS helper (same pattern as attendance_geo_helper.dart)
// ─────────────────────────────────────────────
Future<Map<String, double>?> _getSiteGps() async {
  if (kIsWeb) return null;
  try {
    // 1) Ensure the location service is ON — notify in-app instead of jumping to system settings
    bool svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) {
      await GpsNotificationService.requestEnable();
      // Wait briefly so the user can toggle GPS from the notification, then retry.
      await Future.delayed(const Duration(seconds: 3));
      svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return null;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      // Retry once in-app — do NOT open the system location settings page.
      final pos2 = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return {'lat': pos2.latitude, 'lng': pos2.longitude};
    }
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────
//  Projects List Page
// ─────────────────────────────────────────────
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool ld = true;
  List projects = [];

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => ld = true);
    try {
      projects = await ProjectCache.get(ApiService(), forceRefresh: forceRefresh);
    } catch (e) {
      toast('Failed to load projects: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  void _openProjectForm({Map? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectFormSheet(
        existing: existing,
        onSaved: () {
          // Invalidate cache so other pages (Dashboard, Tasks, etc.) get
          // fresh project data after a create / update.
          ProjectCache.invalidate();
          _load(forceRefresh: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProjectForm(),
        icon: const Icon(Icons.add),
        label: Text(AppStrings.t('proj.newProject')),
        backgroundColor: AppColors.accent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: ld
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: projects.isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: Text(AppStrings.t('proj.noProjects'),
                                    style: TextStyle(color: AppColors.textMuted)),
                              ),
                            )
                          ])
                        : LayoutBuilder(
                            builder: (ctx, constraints) {
                              if (constraints.maxWidth < AppBreakpoints.phone) {
                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                                  itemCount: projects.length,
                                  itemBuilder: (ctx, i) => _projectCard(projects[i]),
                                );
                              }
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: AppSpacing.md,
                                  crossAxisSpacing: AppSpacing.md,
                                  childAspectRatio: 1.45,
                                ),
                                itemCount: projects.length,
                                itemBuilder: (ctx, i) => _projectCard(projects[i], inGrid: true),
                              );
                            },
                          ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _markProjectComplete(Map p) async {
    final pid = p['project_id'];
    if (pid == null) return;
    try {
      await ApiService().updateProject(pid, {'status': 'completed'});
      toast(AppStrings.t('proj.markCompletedDone'));
      if (mounted) _load();
    } catch (e) {
      toast('${AppStrings.t('proj.markCompletedFailed')}: $e');
    }
  }

  Widget _projectCard(Map p, {bool inGrid = false}) {
    final progress = (p['progress'] as num? ?? 0).toDouble();
    final workerCount = p['worker_count'] ?? p['tracked_workers'] ?? 0;
    final radius = (p['fence_radius'] as num? ?? 5000).toInt();
    return sectionCard(
      margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProjectDetailPage(projectId: p['project_id']))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(p['project_name'] ?? '-',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                statusPill(p['status'] ?? 'planning'),
                if ((p['status'] ?? 'planning') != 'completed' && progress >= 100) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _markProjectComplete(p),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.greenLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.green),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                // Edit button
                GestureDetector(
                  onTap: () => _openProjectForm(existing: Map<String, dynamic>.from(p)),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.bgMain,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.edit_outlined, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Expanded(child: Text(p['location_address'] ?? '-',
                  style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            // Geofence badge
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.gps_fixed_rounded, size: 11, color: AppColors.green),
                  const SizedBox(width: 4),
                  Text('Geofence: ${radius}m radius',
                      style: GoogleFonts.outfit(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (workerCount > 0) ...[
                const SizedBox(width: 10),
                Text('$workerCount workers tracked',
                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600)),
              ],
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 7, backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${progress.toStringAsFixed(0)}% complete',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
              if (p['end_date'] != null)
                Text('Due ${DateHelper.tryFormatShort(p['end_date'])}',
                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Project Create / Edit Bottom Sheet with Geofence Picker
// ─────────────────────────────────────────────
class _ProjectFormSheet extends StatefulWidget {
  final Map? existing;
  final VoidCallback onSaved;
  const _ProjectFormSheet({this.existing, required this.onSaved});
  @override
  State<_ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _ProjectFormSheetState extends State<_ProjectFormSheet> {
  final _name = TextEditingController();
  final _loc  = TextEditingController();
  DateTime? _start, _end;
  double _lat = 3.1390, _lng = 101.6869; // default: KL
  double _radius = 5000.0; // meters (default 5km)
  bool _hasGps = false;
  bool _gpsFailed = false;
  bool _saving = false;
  bool _gpsLoading = false;

  // ── Language switch (English / Bahasa Melayu) ──
  String _lang = 'en';
  String t(String en, String bm) => _lang == 'bm' ? bm : en;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e['project_name'] ?? '';
      _loc.text  = e['location_address'] ?? '';
      _lat    = (e['center_lat'] as num?)?.toDouble() ?? 3.1390;
      _lng    = (e['center_lng'] as num?)?.toDouble() ?? 101.6869;
      _radius = (e['fence_radius'] as num?)?.toDouble() ?? 5000.0;
      // Edit mode also requires re-capturing the location before saving, to prevent silently using stale coordinates
      _hasGps = false;
      _gpsFailed = false;
      if (e['start_date'] != null) _start = DateTime.tryParse(e['start_date'].toString());
      if (e['end_date']   != null) _end   = DateTime.tryParse(e['end_date'].toString());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _loc.dispose();
    super.dispose();
  }

  Future<void> _getGps() async {
    setState(() => _gpsLoading = true);
    final pos = await _getSiteGps();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _lat = pos['lat']!;
        _lng = pos['lng']!;
        _hasGps = true;
        _gpsFailed = false;
        _gpsLoading = false;
      });
      toast(t('Site location captured!', 'Lokasi tapak berjaya ditangkap!'));
    } else {
      setState(() {
        _hasGps = false;
        _gpsFailed = true;
        _gpsLoading = false;
      });
      toast(t('Location failed. Please enable GPS and try again.', 'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.'));
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null && mounted) setState(() => isStart ? _start = d : _end = d);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { toast(t('Project name is required', 'Nama projek diperlukan')); return; }
    if (_loc.text.trim().isEmpty)  { toast(t('Location address is required', 'Alamat tapak diperlukan')); return; }
    if (!_hasGps) {
      toast(_gpsFailed ? t('Location failed. Please enable GPS and try again.', 'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.') : t('Please capture the site GPS location first', 'Sila tangkap lokasi GPS tapak dahulu'));
      return;
    }

    setState(() => _saving = true);
    try {
      final body = {
        'project_name':     _name.text.trim(),
        'location_address': _loc.text.trim(),
        'center_lat':   _lat,
        'center_lng':   _lng,
        'fence_radius': _radius,
        'start_date': _start?.toIso8601String().split('T').first,
        'end_date':   _end?.toIso8601String().split('T').first,
        'status':   widget.existing?['status'] ?? 'planning',
        'progress': widget.existing?['progress'] ?? 0.0,
      };

      if (_isEdit) {
        await ApiService().updateProject(widget.existing!['project_id'], body);
      } else {
        await ApiService().createProject(body);
      }

      if (!mounted) return;
      Navigator.pop(context);
      toast(_isEdit ? t('Project updated!', 'Projek dikemas kini!') : t('Project created!', 'Projek dicipta!'));
      widget.onSaved();
    } on DioException catch (e) {
      toast(e.message ?? t('Failed to save project', 'Gagal menyimpan projek'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime? d) => d == null ? t('Not set', 'Tidak ditetapkan')
      : DateHelper.formatShort(d);

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Expanded(
              child: Text(_isEdit ? t('Edit Project', 'Sunting Projek') : t('New Project', 'Projek Baharu'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            // ── Language switch button ──
            TextButton.icon(
              onPressed: () => setState(() => _lang = _lang == 'en' ? 'bm' : 'en'),
              icon: Icon(_lang == 'en' ? Icons.translate_rounded : Icons.language_rounded, size: 16),
              label: Text(_lang == 'en' ? 'BM' : 'EN',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Project Name ──────────────────────────────
          Text(t('Project Name', 'Nama Projek'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              hintText: t('e.g. Penang Tower Block C', 'cth. Menara Pulau Pinang Blok C'),
              hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
              filled: true, fillColor: AppColors.bgMain,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // ── Location Address ──────────────────────────
          Text(t('Site Address', 'Alamat Tapak'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _loc,
            decoration: InputDecoration(
              hintText: t('Full address of the construction site', 'Alamat penuh tapak pembinaan'),
              hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
              filled: true, fillColor: AppColors.bgMain,
              prefixIcon: Icon(Icons.place_outlined, color: AppColors.textMuted, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),

          // ── GPS GEOFENCE SECTION ──────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hasGps
                  ? AppColors.greenLight
                  : (_gpsFailed ? AppColors.red.withValues(alpha: 0.06) : AppColors.bgMain),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _hasGps
                      ? AppColors.green
                      : (_gpsFailed ? AppColors.red : AppColors.border)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.gps_fixed_rounded, size: 16, color: _hasGps ? AppColors.green : AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t('Site Geofence', 'Geopagar Tapak'),
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700,
                          color: _hasGps ? AppColors.green : AppColors.textPrimary)),
                ),
                if (_hasGps)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(8)),
                    child: Text(t('Set', 'Tetap'), style: GoogleFonts.outfit(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 10),

              // GPS coordinates display
              if (_hasGps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(Icons.location_on, size: 12, color: AppColors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Lat: ${_lat.toStringAsFixed(5)},  Lng: ${_lng.toStringAsFixed(5)}',
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ]),
                ),

              // Fence map — tap to move center
              _FenceMap(
                lat: _lat,
                lng: _lng,
                radiusMeters: _radius,
                height: 200,
                onTap: (p) => setState(() {
                  _lat = p.latitude;
                  _lng = p.longitude;
                  _hasGps = true;
                  _gpsFailed = false;
                }),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.touch_app_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(t('Tap on the map to move the fence center', 'Ketik peta untuk menggerakkan pusat pagar'),
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                ),
              ]),
              const SizedBox(height: 12),

              // GPS failure hint
              if (_gpsFailed) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(Icons.error_outline, size: 14, color: AppColors.red),
                    const SizedBox(width: 6),
                    Text(t('Location failed. Please enable GPS and try again.', 'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.'),
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red)),
                  ]),
                ),
              ],

              // Get GPS button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _gpsLoading ? null : _getGps,
                  icon: _gpsLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(_hasGps ? t('Re-capture Site Location', 'Tangkap Semula Lokasi Tapak') : t('Capture Site Location (Go to site first)', 'Tangkap Lokasi Tapak (Pergi ke tapak dahulu)'),
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _hasGps ? AppColors.green : AppColors.accent,
                    side: BorderSide(color: _hasGps ? AppColors.green : AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Radius slider
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Check-in Radius', 'Jejari Daftar Masuk'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('${_radius.toInt()} m',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
                ),
              ]),
              Slider(
                value: _radius,
                min: 50, max: 5000,
                divisions: 99,
                activeColor: AppColors.accent,
                inactiveColor: AppColors.border,
                onChanged: (v) => setState(() => _radius = v),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('50m (tight)', '50m (ketat)'), style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text(t('Workers must be within this distance to check in', 'Pekerja mesti berada dalam jarak ini untuk daftar masuk'),
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text('5000m', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Dates ─────────────────────────────────────
          Row(children: [
            Expanded(
              child: _DateButton(
                label: t('Start Date', 'Tarikh Mula'),
                value: _fmtDate(_start),
                onTap: () => _pickDate(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateButton(
                label: t('End Date', 'Tarikh Tamat'),
                value: _fmtDate(_end),
                onTap: () => _pickDate(false),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Save Button ───────────────────────────────
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? t('Save Changes', 'Simpan Perubahan') : t('Create Project', 'Cipta Projek'),
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _DateButton({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Project Detail Page
// ─────────────────────────────────────────────
class ProjectDetailPage extends StatefulWidget {
  final int projectId;
  const ProjectDetailPage({super.key, required this.projectId});
  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool ld = true;
  Map? project;
  List tasks = [];

  // Attendance time-window settings (same fields/logic as attendance_page)
  bool _settingsLd = true;
  Map _settings = {};
  final _checkInStart = TextEditingController();
  final _checkInEnd = TextEditingController();
  final _checkOutStart = TextEditingController();
  final _checkOutEnd = TextEditingController();
  final _breakStart = TextEditingController();
  final _breakEnd = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
    _loadSettings();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _checkInStart.dispose();
    _checkInEnd.dispose();
    _checkOutStart.dispose();
    _checkOutEnd.dispose();
    _breakStart.dispose();
    _breakEnd.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      _settings = await ApiService().getSettings();
      _checkInStart.text = _settings['check_in_start'] ?? '08:00';
      _checkInEnd.text = _settings['check_in_end'] ?? '10:30';
      _checkOutStart.text = _settings['check_out_start'] ?? '15:00';
      _checkOutEnd.text = _settings['check_out_end'] ?? '17:00';
      _breakStart.text = _settings['break_start'] ?? '12:00';
      _breakEnd.text = _settings['break_end'] ?? '13:00';
    } catch (_) {
    } finally {
      if (mounted) setState(() => _settingsLd = false);
    }
  }

  bool _validHHMM(String s) {
    final parts = s.trim().split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }

  Future<void> _saveSettings() async {
    final vals = [
      _checkInStart.text, _checkInEnd.text,
      _checkOutStart.text, _checkOutEnd.text,
      _breakStart.text, _breakEnd.text,
    ];
    if (vals.any((v) => !_validHHMM(v))) {
      toast('All times must use HH:MM 24-hour format (e.g. 08:00)');
      return;
    }
    try {
      await ApiService().updateSettings({
        ..._settings,
        'check_in_start': _checkInStart.text.trim(),
        'check_in_end': _checkInEnd.text.trim(),
        'check_out_start': _checkOutStart.text.trim(),
        'check_out_end': _checkOutEnd.text.trim(),
        'break_start': _breakStart.text.trim(),
        'break_end': _breakEnd.text.trim(),
      });
      toast('Attendance windows saved');
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to save settings');
    }
  }

  Widget _timeField(TextEditingController ctrl, String label) => Expanded(
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label, helperText: 'HH:MM'),
        ),
      );

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final all = await ProjectCache.get(ApiService());
      project = all.firstWhere((p) => p['project_id'] == widget.projectId, orElse: () => null);
      tasks = await ApiService().getTasks(widget.projectId);
    } catch (e) {
      toast('Failed to load project: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _markProjectComplete() async {
    final p = project;
    if (p == null) return;
    try {
      await ApiService().updateProject(p['project_id'], {'status': 'completed'});
      ProjectCache.invalidate(); // refresh list for other pages
      toast(AppStrings.t('proj.markCompletedDone'));
      if (mounted) _load();
    } catch (e) {
      toast('${AppStrings.t('proj.markCompletedFailed')}: $e');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return Scaffold(backgroundColor: AppColors.bgMain, body: Center(child: CircularProgressIndicator()));
    if (project == null) return Scaffold(backgroundColor: AppColors.bgMain, body: Center(child: Text(AppStrings.t('proj.projectNotFound'))));
    final p = project!;
    final completed = tasks.where((t) => t['status'] == 'completed').length;
    final radius = (p['fence_radius'] as num?)?.toInt() ?? 5000;
    final lat = (p['center_lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (p['center_lng'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(p['project_name'] ?? 'Project',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          TextButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _ProjectFormSheet(
                  existing: Map<String, dynamic>.from(p),
                  onSaved: _load,
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(AppStrings.t('proj.edit')),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.sidebarBg, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(p['project_name'] ?? '-',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
              if ((p['status'] ?? 'planning') != 'completed' &&
                  ((p['progress'] ?? 0) as num).toDouble() >= 100) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _markProjectComplete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text('Complete',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
              statusPill(p['status'] ?? 'planning'),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.place_outlined, size: 13, color: AppColors.textSidebarMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(p['location_address'] ?? '-',
                  style: TextStyle(color: AppColors.textSidebarMuted, fontSize: 14))),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(AppStrings.t('proj.overallCompletion'), style: TextStyle(color: AppColors.textSidebarMuted, fontSize: 13)),
              Text('${p['progress']?.toStringAsFixed(0) ?? 0}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((p['progress'] ?? 0) as num) / 100,
                minHeight: 8, backgroundColor: AppColors.sidebarHover,
                valueColor: AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Geofence Info Card ────────────────────────
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.greenLight, shape: BoxShape.circle),
                child: Icon(Icons.gps_fixed_rounded, size: 16, color: AppColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppStrings.t('proj.siteGeofence'),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                  Text(AppStrings.t('proj.geofenceHint').replaceAll('{radius}', '$radius'),
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
              statusPill('active'),
            ]),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _infoRow(Icons.radar_rounded, 'Radius', '$radius meters'),
            const SizedBox(height: 8),
            _infoRow(Icons.my_location_rounded, 'Center GPS',
                'Lat ${lat.toStringAsFixed(5)},  Lng ${lng.toStringAsFixed(5)}'),
            const SizedBox(height: 14),
            if (lat != 0.0 || lng != 0.0)
              _FenceMap(lat: lat, lng: lng, radiusMeters: radius.toDouble(), height: 200),
          ]),
        ),
        const SizedBox(height: 16),

        // Dates
        Row(children: [
          Expanded(child: statCard(label: 'Start', value: DateHelper.tryFormatShort(p['start_date'], fallback: '—'))),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Due', value: DateHelper.tryFormatShort(p['end_date'], fallback: '—'))),
        ]),
        const SizedBox(height: 16),

        // Tasks
        Text(AppStrings.t('proj.taskSummary'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: statCard(label: 'Total', value: '${tasks.length}')),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Done', value: '$completed', iconColor: AppColors.green)),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Left', value: '${tasks.length - completed}', iconColor: AppColors.accent)),
        ]),
        const SizedBox(height: 16),

        // ── Attendance Time Window Settings ─────────────────────
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.greenLight, shape: BoxShape.circle),
                child: Icon(Icons.schedule_rounded, size: 16, color: AppColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Attendance Time Window',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              ),
              if (!_settingsLd)
                TextButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: Text(AppStrings.t('proj.edit')),
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                ),
            ]),
            const SizedBox(height: 6),
            Text('Work start / late threshold / check-out window',
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            if (_settingsLd)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else ...[
              Row(children: [
                _timeField(_checkInStart, 'Check-in start'),
                const SizedBox(width: 10),
                _timeField(_checkInEnd, 'Late threshold'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _timeField(_checkOutStart, 'Check-out start'),
                const SizedBox(width: 10),
                _timeField(_checkOutEnd, 'Check-out end'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _timeField(_breakStart, 'Break start'),
                const SizedBox(width: 10),
                _timeField(_breakEnd, 'Break end'),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // ── Tasks: list + Add New Task ──────────────────────────
        Row(children: [
          Expanded(
            child: Text(AppStrings.t('proj.taskSummary'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final created = await showDialog<bool>(
                context: context,
                builder: (_) => TaskForm(initialProjectId: widget.projectId),
              );
              if (created == true) _load();
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add New Task'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.green,
              side: BorderSide(color: AppColors.green),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          sectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No tasks yet — tap Add New Task to create one.',
                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
              ),
            ),
          )
        else
          ...tasks.map((t) {
            final name = t['task_name'] ?? '-';
            final status = t['status'] ?? 'todo';
            final priority = t['priority'] ?? 'medium';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TaskDetailPage(task: Map<String, dynamic>.from(t))),
                  );
                  if (mounted) _load();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(color: AppColors.greenLight, shape: BoxShape.circle),
                        child: Icon(
                          status == 'completed' ? Icons.check_rounded : Icons.construction_rounded,
                          size: 16, color: AppColors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                      const SizedBox(width: 8),
                      _priorityChip(priority),
                      const SizedBox(width: 8),
                      statusPill(status),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
                    ]),
                    const SizedBox(height: 6),
                    // Second row: due date · assigned worker (single line, never wraps vertically)
                    Padding(
                      padding: const EdgeInsets.only(left: 46),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            '${DateHelper.tryFormatShort(t['due_date'], fallback: 'No due date')}  ·  ${t['assigned_workers'] is List && (t['assigned_workers'] as List).isNotEmpty ? '${(t['assigned_workers'] as List).length} worker(s)' : 'Unassigned'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _quickStatusBtn(t, 'pending', Icons.radio_button_unchecked_rounded, AppColors.yellow),
                        _quickStatusBtn(t, 'in_progress', Icons.play_arrow_rounded, AppColors.blue),
                        _quickStatusBtn(t, 'completed', Icons.check_rounded, AppColors.green),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          }),
      ]),
    );
  }

  Future<void> _setTaskStatus(Map t, String newStatus) async {
    final taskId = t['task_id'];
    if (taskId == null) { toast('Invalid task'); return; }
    try {
      await ApiService().updateTask(taskId, {'status': newStatus});
      t['status'] = newStatus;
      toast('Task marked $newStatus');
      if (mounted) _load();
    } catch (e) {
      toast('Failed to update task: $e');
    }
  }

  Widget _quickStatusBtn(Map t, String value, IconData icon, Color color) {
    final active = t['status'] == value;
    return IconButton(
      onPressed: () => _setTaskStatus(t, value),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: value.replaceAll('_', ' '),
      icon: Icon(icon,
          size: 18, color: active ? color : AppColors.textMuted),
    );
  }

  Widget _priorityChip(String priority) {
    final p = priority.toLowerCase();
    final color = p == 'high'
        ? AppColors.red
        : p == 'low'
            ? AppColors.blue
            : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(priority,
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        Expanded(child: Text(value, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary))),
      ]);
}
