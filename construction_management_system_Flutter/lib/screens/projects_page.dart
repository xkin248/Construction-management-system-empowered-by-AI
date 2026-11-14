import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/photo_capture.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../services/task_status_notifier.dart';
import '../services/gps_notification_service.dart';
import '../l10n/app_strings.dart';
import '../utils/date_helper.dart';
import '../widgets/task_form.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/project_card.dart';
import '../widgets/worker_list_card.dart';
import '../widgets/file_tiles.dart';
import 'tasks_page.dart' show TaskDetailPage;
import '../widgets/a11y.dart';
import '../models/file.dart';
import '../widgets/dashboard/dashboard_section_parts.dart';
import '../widgets/supervisor/attendance_photo_viewer.dart';
import 'worker_detail_page.dart';

// ─────────────────────────────────────────────
//  Fence Map (OpenStreetMap free tiles) — center marker + radius circle
// ─────────────────────────────────────────────
class _FenceMap extends StatefulWidget {
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
  State<_FenceMap> createState() => _FenceMapState();
}

class _FenceMapState extends State<_FenceMap> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant _FenceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FlutterMap applies initialCenter only at first build.  Explicitly move
    // after a fresh GPS capture so the visible map follows the new pin.
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(LatLng(widget.lat, widget.lng), 16);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.lat, widget.lng);
    return ClipRRect(
      borderRadius: AppRadius.rMd,
      child: SizedBox(
        height: widget.height,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            onTap: widget.onTap == null
                ? null
                : (tapPos, latLng) => widget.onTap!(latLng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.buildsmart.app',
            ),
            CircleLayer(circles: [
              CircleMarker(
                point: center,
                radius: widget.radiusMeters <= 0 ? 5000 : widget.radiusMeters,
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
                child: Icon(Icons.location_on_rounded,
                    color: AppColors.red, size: 38),
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
      if (!svc) {
        return null;
      }
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      // Retry once in-app — do NOT open the system location settings page.
      final pos2 = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
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
bool _isTaskComplete(dynamic status) {
  final value = (status ?? '').toString().toLowerCase();
  return value == 'approved' || value == 'completed' || value == 'done';
}

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool ld = true;
  List projects = [];
  Object? _loadError;

  /// Drives the always-visible scrollbar of the project list.
  final ScrollController _scrollCtrl = ScrollController();

  // ── Search + status scope (spec PART B4) ──
  String _q = '';
  String _scope = 'all';
  final TextEditingController _searchCtrl = TextEditingController();

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
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      ld = true;
      _loadError = null;
    });
    try {
      projects =
          await ProjectCache.get(ApiService(), forceRefresh: forceRefresh);
    } catch (e) {
      _loadError = e;
      toast('Failed to load projects: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  void _openProjectForm({Map? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
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

  String _t(String en, String zh, String ms) => AppSettings.t(en, zh, ms);

  /// Projects matching the search text and the status scope.
  List get _visible {
    final q = _q.trim().toLowerCase();
    return projects.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      bool inScope;
      switch (_scope) {
        case 'active':
          inScope = !['completed', 'done', 'archived', 'on_hold', 'cancelled']
              .contains(status);
          break;
        case 'completed':
          inScope = ['completed', 'done'].contains(status);
          break;
        case 'archived':
          inScope = ['archived', 'on_hold', 'cancelled'].contains(status);
          break;
        default:
          inScope = true;
      }
      if (!inScope) return false;
      if (q.isEmpty) return true;
      final hay =
          '${p['project_name'] ?? ''} ${p['location'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Search field + All / Active / Completed / Archived segments (spec B4).
  Widget _filterBar({required bool isPhone}) {
    final scopes = {
      'all': _t('All', '全部', 'Semua'),
      'active': _t('Active', '进行中', 'Aktif'),
      'completed': _t('Completed', '已完成', 'Selesai'),
      'archived': _t('Archived', '已归档', 'Arkib'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _q = v),
          textInputAction: TextInputAction.search,
          style: GoogleFonts.inter(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: _t(
                'Search projects or site', '搜索项目或工地', 'Cari projek atau tapak'),
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search_rounded,
                size: 18, color: AppColors.textMuted),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    tooltip: _t('Clear search', '清除搜索', 'Kosongkan'),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _q = '');
                    },
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: AppColors.textMuted),
                  ),
            isDense: true,
            filled: true,
            fillColor: AppColors.bgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in scopes.entries) ...[
              _scopeChip(e.key, e.value),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _scopeChip(String key, String label) {
    final selected = _scope == key;
    return InkWell(
      onTap: () => setState(() => _scope = key),
      borderRadius: AppRadius.rSm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSolid : AppColors.bgCard,
          borderRadius: AppRadius.rSm,
          border: Border.all(
              color: selected ? AppColors.accentSolid : AppColors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.onAccent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: const ValueKey('fab_projects'),
        onPressed: () => _openProjectForm(),
        icon: const Icon(Icons.add),
        label: Text(AppStrings.t('proj.newProject')),
        backgroundColor: AppColors.accent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              AppPageIntro(
                icon: Icons.apartment_rounded,
                enTitle: 'PROJECTS',
                msTitle: 'PROJEK',
                zhTitle: '项目',
                enSubtitle: 'Track site progress and deadlines',
                msSubtitle: 'Pantau kemajuan dan tarikh',
                zhSubtitle: '查看工地进度与期限',
                worker: false,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (ctx, cs) =>
                    _filterBar(isPhone: cs.maxWidth < AppBreakpoints.phone),
              ),
              Expanded(
                child: ld
                    ? const SkeletonList(rows: 5)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: AppScrollbar(
                          controller: _scrollCtrl,
                          child: visible.isEmpty
                              ? ListView(
                                  controller: _scrollCtrl,
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.55,
                                      child: _loadError != null
                                          ? FailureState(
                                              error: _loadError,
                                              onRetry: () =>
                                                  _load(forceRefresh: true),
                                            )
                                          : (projects.isEmpty
                                              ? GuidedEmptyState(
                                                  icon: Icons
                                                      .account_tree_outlined,
                                                  title: AppStrings.t(
                                                      'empty.projects.title'),
                                                  description: AppStrings.t(
                                                      'empty.projects.desc'),
                                                  primaryLabel: AppStrings.t(
                                                      'empty.projects.action'),
                                                  onPrimary: () =>
                                                      _openProjectForm(),
                                                )
                                              : DashboardEmptyBox(
                                                  _t(
                                                      'No project matches this filter',
                                                      '没有符合筛选条件的项目',
                                                      'Tiada projek sepadan'),
                                                  icon: Icons
                                                      .filter_alt_off_rounded,
                                                )),
                                    ),
                                  ],
                                )
                              : LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    if (constraints.maxWidth <
                                        AppBreakpoints.phone) {
                                      return ListView.builder(
                                        controller: _scrollCtrl,
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 24),
                                        itemCount: visible.length,
                                        addAutomaticKeepAlives: false,
                                        addRepaintBoundaries: true,
                                        itemBuilder: (ctx, i) =>
                                            _buildCard(visible[i]),
                                      );
                                    }
                                    return GridView.builder(
                                      controller: _scrollCtrl,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 24),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: AppSpacing.md,
                                        crossAxisSpacing: AppSpacing.md,
                                        mainAxisExtent: 210,
                                      ),
                                      itemCount: visible.length,
                                      addAutomaticKeepAlives: false,
                                      itemBuilder: (ctx, i) =>
                                          _buildCard(visible[i], inGrid: true),
                                    );
                                  },
                                ),
                        ),
                      ),
              ),
            ]),
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

  /// Builds one lazy list item; the card itself lives in its own widget so a
  /// scroll rebuild does not re-run this page's whole builder closure.
  Widget _buildCard(Map p, {bool inGrid = false}) {
    return ProjectCard(
      key: ValueKey('proj-${p['project_id']}'),
      project: p,
      inGrid: inGrid,
      onOpen: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProjectDetailPage(projectId: p['project_id']))),
      onEdit: () => _openProjectForm(existing: Map<String, dynamic>.from(p)),
      onMarkComplete: () => _markProjectComplete(p),
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
  final _loc = TextEditingController();
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
      _loc.text = e['location_address'] ?? '';
      _lat = (e['center_lat'] as num?)?.toDouble() ?? 3.1390;
      _lng = (e['center_lng'] as num?)?.toDouble() ?? 101.6869;
      _radius = (e['fence_radius'] as num?)?.toDouble() ?? 5000.0;
      // Edit mode also requires re-capturing the location before saving, to prevent silently using stale coordinates
      _hasGps = false;
      _gpsFailed = false;
      if (e['start_date'] != null) {
        _start = DateTime.tryParse(e['start_date'].toString());
      }
      if (e['end_date'] != null) {
        _end = DateTime.tryParse(e['end_date'].toString());
      }
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
      toast(t('Location failed. Please enable GPS and try again.',
          'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.'));
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
    if (_name.text.trim().isEmpty) {
      toast(t('Project name is required', 'Nama projek diperlukan'));
      return;
    }
    if (_loc.text.trim().isEmpty) {
      toast(t('Location address is required', 'Alamat tapak diperlukan'));
      return;
    }
    if (!_hasGps) {
      // Auto-capture the site location on save so the button never appears
      // unresponsive; only block when the GPS fix itself fails.
      _gpsFailed = false;
      await _getGps();
      if (!mounted) return;
      if (!_hasGps) {
        toast(_gpsFailed
            ? t('Location failed. Please enable GPS and try again.',
                'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.')
            : t('Please capture the site GPS location first',
                'Sila tangkap lokasi GPS tapak dahulu'));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final body = {
        'project_name': _name.text.trim(),
        'location_address': _loc.text.trim(),
        'center_lat': _lat,
        'center_lng': _lng,
        'fence_radius': _radius,
        'start_date': _start?.toIso8601String().split('T').first,
        'end_date': _end?.toIso8601String().split('T').first,
        'status': widget.existing?['status'] ?? 'planning',
        'progress': widget.existing?['progress'] ?? 0.0,
      };

      if (_isEdit) {
        await ApiService().updateProject(widget.existing!['project_id'], body);
      } else {
        await ApiService().createProject(body);
      }

      if (!mounted) return;
      Navigator.pop(context);
      toast(_isEdit
          ? t('Project updated!', 'Projek dikemas kini!')
          : t('Project created!', 'Projek dicipta!'));
      widget.onSaved();
    } on DioException catch (e) {
      toast(e.message ?? t('Failed to save project', 'Gagal menyimpan projek'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime? d) =>
      d == null ? t('Not set', 'Tidak ditetapkan') : DateHelper.formatShort(d);

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
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
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border, borderRadius: AppRadius.rHair),
                ),
              ),
              Row(children: [
                Expanded(
                  child: Text(
                      _isEdit
                          ? t('Edit Project', 'Sunting Projek')
                          : t('New Project', 'Projek Baharu'),
                      style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
                // ── Language switch button ──
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _lang = _lang == 'en' ? 'bm' : 'en'),
                  icon: Icon(
                      _lang == 'en'
                          ? Icons.translate_rounded
                          : Icons.language_rounded,
                      size: 16),
                  label: Text(_lang == 'en' ? 'BM' : 'EN',
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              // ── Project Name ──────────────────────────────
              Text(t('Project Name', 'Nama Projek'),
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  hintText: t('e.g. Penang Tower Block C',
                      'cth. Menara Pulau Pinang Blok C'),
                  hintStyle: GoogleFonts.inter(
                      color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgMain,
                  border: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide: BorderSide(color: AppColors.border)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // ── Location Address ──────────────────────────
              Text(t('Site Address', 'Alamat Tapak'),
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _loc,
                decoration: InputDecoration(
                  hintText: t('Full address of the construction site',
                      'Alamat penuh tapak pembinaan'),
                  hintStyle: GoogleFonts.inter(
                      color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgMain,
                  prefixIcon: Icon(Icons.place_outlined,
                      color: AppColors.textMuted, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide: BorderSide(color: AppColors.border)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // ── GPS GEOFENCE SECTION ──────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _hasGps
                      ? AppColors.greenLight
                      : (_gpsFailed
                          ? AppColors.red.withValues(alpha: 0.06)
                          : AppColors.bgMain),
                  borderRadius: AppRadius.rMd,
                  border: Border.all(
                      color: _hasGps
                          ? AppColors.green
                          : (_gpsFailed ? AppColors.red : AppColors.border)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.gps_fixed_rounded,
                            size: 16,
                            color: _hasGps
                                ? AppColors.green
                                : AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t('Site Geofence', 'Geopagar Tapak'),
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _hasGps
                                      ? AppColors.green
                                      : AppColors.textPrimary)),
                        ),
                        if (_hasGps)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.green,
                                borderRadius: AppRadius.rMd),
                            child: Text(t('Set', 'Tetap'),
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: AppColors.onAccent,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 12),

                      // GPS coordinates display
                      if (_hasGps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(children: [
                            Icon(Icons.location_on,
                                size: 12, color: AppColors.green),
                            const SizedBox(width: 4),
                            Text(
                              'Lat: ${_lat.toStringAsFixed(5)},  Lng: ${_lng.toStringAsFixed(5)}',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: AppColors.textSecondary),
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
                        Icon(Icons.touch_app_outlined,
                            size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                              t('Tap on the map to move the fence center',
                                  'Ketik peta untuk menggerakkan pusat pagar'),
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: AppColors.textMuted)),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // GPS failure hint
                      if (_gpsFailed) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(children: [
                            Icon(Icons.error_outline,
                                size: 14, color: AppColors.red),
                            const SizedBox(width: 8),
                            Text(
                                t('Location failed. Please enable GPS and try again.',
                                    'Lokasi gagal. Sila hidupkan GPS dan cuba lagi.'),
                                style: GoogleFonts.inter(
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
                              ? const SizedBox(
                                  width: 16,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location_rounded, size: 16),
                          label: Text(
                              _hasGps
                                  ? t('Refresh My Current Location',
                                      'Muat Semula Lokasi Semasa Saya')
                                  : t('Use My Current Location',
                                      'Guna Lokasi Semasa Saya'),
                              style: GoogleFonts.inter(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                _hasGps ? AppColors.green : AppColors.accent,
                            side: BorderSide(
                                color: _hasGps
                                    ? AppColors.green
                                    : AppColors.accent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Radius slider
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t('Check-in Radius', 'Jejari Daftar Masuk'),
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.12),
                                  borderRadius: AppRadius.rMd),
                              child: Text('${_radius.toInt()} m',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.accent)),
                            ),
                          ]),
                      Slider(
                        value: _radius,
                        min: 50,
                        max: 5000,
                        divisions: 99,
                        activeColor: AppColors.accent,
                        inactiveColor: AppColors.border,
                        onChanged: (v) => setState(() => _radius = v),
                      ),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t('50m (tight)', '50m (ketat)'),
                                style: GoogleFonts.inter(
                                    fontSize: 14, color: AppColors.textMuted)),
                            Text(
                                t('Workers must be within this distance to check in',
                                    'Pekerja mesti berada dalam jarak ini untuk daftar masuk'),
                                style: GoogleFonts.inter(
                                    fontSize: 14, color: AppColors.textMuted)),
                            Text('5000m',
                                style: GoogleFonts.inter(
                                    fontSize: 14, color: AppColors.textMuted)),
                          ]),
                    ]),
              ),
              const SizedBox(height: 16),

              // ── Dates ─────────────────────────────────────
              Row(children: [
                Expanded(
                  child: _DateButton(
                    label: t('Start Date', 'Tarikh Mula'),
                    value: _fmtDate(_start),
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 12),
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
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentInk))
                    : Text(
                        _isEdit
                            ? t('Save Changes', 'Simpan Perubahan')
                            : t('Create Project', 'Cipta Projek'),
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ]),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
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
  Object? _loadError;

  // ── Detail tabs (spec PART B4) ──
  int _tab = 0;
  List _workers = [];
  List _attendance = [];
  List _common = [];
  List<FileItem> _files = [];
  List _history = []; // Common-task completion log (last 14 days)

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
      _checkInStart.text,
      _checkInEnd.text,
      _checkOutStart.text,
      _checkOutEnd.text,
      _breakStart.text,
      _breakEnd.text,
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
      project = all.firstWhere((p) => p['project_id'] == widget.projectId,
          orElse: () => null);
      final res = await Future.wait([
        ApiService().getTasks(widget.projectId),
        ApiService().getWorkers(pid: widget.projectId),
        ApiService().attendanceToday(pid: widget.projectId),
        ApiService().commonTasksToday(projectId: widget.projectId),
        ApiService().getFiles(pid: widget.projectId),
        ApiService().commonTaskHistory(projectId: widget.projectId, days: 14),
      ]);
      tasks = res[0] as List;
      _workers = res[1] as List;
      _attendance = ((res[2] as Map)['workers'] as List?) ??
          ((res[2] as Map)['rows'] as List?) ??
          const [];
      _common = ((res[3] as Map)['tasks'] as List?) ?? const [];
      _files = (res[4] as List)
          .map((e) => FileItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _history = (res[5] as List?) ?? const [];
      _loadError = null;
    } catch (e) {
      _loadError = e;
      toast('Failed to load project: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _markProjectComplete() async {
    final p = project;
    if (p == null) return;
    try {
      await ApiService()
          .updateProject(p['project_id'], {'status': 'completed'});
      ProjectCache.invalidate(); // refresh list for other pages
      toast(AppStrings.t('proj.markCompletedDone'));
      if (mounted) _load();
    } catch (e) {
      toast('${AppStrings.t('proj.markCompletedFailed')}: $e');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) {
      return Scaffold(
        backgroundColor: AppColors.bgMain,
        body: const SkeletonDetail(),
      );
    }
    if (project == null) {
      return Scaffold(
        backgroundColor: AppColors.bgMain,
        body: _loadError != null
            ? FailureState(error: _loadError, onRetry: _load)
            : FailureState(
                kind: FailureKind.unknown,
                title: AppStrings.t('proj.projectNotFound'),
                onRetry: _load,
              ),
      );
    }
    final p = project!;
    final completed = tasks.where((t) => _isTaskComplete(t['status'])).length;
    final radius = (p['fence_radius'] as num?)?.toInt() ?? 5000;
    final lat = (p['center_lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (p['center_lng'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        centerTitle: false,
        title: Text(p['project_name'] ?? 'Project',
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          TextButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.transparent,
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
      body: Column(children: [
        _detailTabStrip(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _overviewTab(p, lat, lng, radius, completed),
              _tasksTab(),
              _workersTab(),
              _attendanceTab(),
              _commonTab(),
              _filesTab(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Tab strip + per-tab views (spec PART B4) ───────────────
  Widget _detailTabStrip() => Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            _tabChip(0, Icons.space_dashboard_outlined,
                AppStrings.t('proj.tabOverview'), null),
            const SizedBox(width: 8),
            _tabChip(1, Icons.checklist_rounded, AppStrings.t('proj.tabTasks'),
                tasks.length),
            const SizedBox(width: 8),
            _tabChip(2, Icons.groups_rounded, AppStrings.t('proj.tabWorkers'),
                _workers.length),
            const SizedBox(width: 8),
            _tabChip(3, Icons.fingerprint_rounded,
                AppStrings.t('proj.tabAttendance'), _attendance.length),
            const SizedBox(width: 8),
            _tabChip(4, Icons.cleaning_services_rounded,
                AppStrings.t('proj.tabCommonTasks'), _common.length),
            const SizedBox(width: 8),
            _tabChip(5, Icons.folder_copy_outlined,
                AppStrings.t('proj.tabFiles'), _files.length),
          ]),
        ),
      );

  Widget _tabChip(int index, IconData icon, String label, int? count) {
    final on = _tab == index;
    final fg = on ? AppColors.onAccent : AppColors.textMuted;
    return semanticTapTarget(
      label: label,
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSolid : AppColors.bgMain,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: on ? AppColors.accentSolid : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: on ? AppColors.onAccentFaint : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('$count',
                    style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _overviewTab(
          Map p, double lat, double lng, int radius, int completed) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _projectHero(p),
        const SizedBox(height: 16),
        _projectPulse(),
        const SizedBox(height: 16),

        // ── Geofence Info Card ────────────────────────
        sectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.greenLight, shape: BoxShape.circle),
                child: Icon(Icons.gps_fixed_rounded,
                    size: 16, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppStrings.t('proj.siteGeofence'),
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                      Text(
                          AppStrings.t('proj.geofenceHint')
                              .replaceAll('{radius}', '$radius'),
                          style: GoogleFonts.inter(
                              fontSize: 13, color: AppColors.textMuted)),
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
            const SizedBox(height: 16),
            if (lat != 0.0 || lng != 0.0)
              _FenceMap(
                  lat: lat,
                  lng: lng,
                  radiusMeters: radius.toDouble(),
                  height: 200),
          ]),
        ),
        const SizedBox(height: 16),

        // Dates
        Row(children: [
          Expanded(
              child: statCard(
                  label: 'Start',
                  value: DateHelper.tryFormatShort(p['start_date'],
                      fallback: '—'))),
          const SizedBox(width: 12),
          Expanded(
              child: statCard(
                  label: 'Due',
                  value:
                      DateHelper.tryFormatShort(p['end_date'], fallback: '—'))),
        ]),
        const SizedBox(height: 16),

        // Tasks
        Text(AppStrings.t('proj.taskSummary'),
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: statCard(label: 'Total', value: '${tasks.length}')),
          const SizedBox(width: 12),
          Expanded(
              child: statCard(
                  label: 'Done',
                  value: '$completed',
                  iconColor: AppColors.green)),
          const SizedBox(width: 12),
          Expanded(
              child: statCard(
                  label: 'Left',
                  value: '${tasks.length - completed}',
                  iconColor: AppColors.accent)),
        ]),
        const SizedBox(height: 16),

        // ── Attendance Time Window Settings ─────────────────────
        sectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.greenLight, shape: BoxShape.circle),
                child: Icon(Icons.schedule_rounded,
                    size: 16, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Attendance Time Window',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
              ),
              if (!_settingsLd)
                TextButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: Text(AppStrings.t('proj.edit')),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.accent),
                ),
            ]),
            const SizedBox(height: 8),
            Text('Work start / late threshold / check-out window',
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            if (_settingsLd)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else ...[
              Row(children: [
                _timeField(_checkInStart, 'Check-in start'),
                const SizedBox(width: 12),
                _timeField(_checkInEnd, 'Late threshold'),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _timeField(_checkOutStart, 'Check-out start'),
                const SizedBox(width: 12),
                _timeField(_checkOutEnd, 'Check-out end'),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _timeField(_breakStart, 'Break start'),
                const SizedBox(width: 12),
                _timeField(_breakEnd, 'Break end'),
              ]),
            ],
          ]),
        ),
      ]);

  /// Real-time project snapshot assembled from project-specific workers,
  /// attendance and task payloads already loaded for this screen.
  Widget _projectPulse() {
    final present = _attendance.where((row) {
      final status = (row['today_status'] ?? row['status'] ?? '').toString();
      return status == 'present' || status == 'late' || status == 'checked_in';
    }).length;
    final late = _attendance
        .where((row) =>
            (row['today_status'] ?? row['status'] ?? '').toString() == 'late')
        .length;
    final remaining =
        tasks.where((task) => !_isTaskComplete(task['status'])).toList()
          ..sort((a, b) {
            final da = DateTime.tryParse((a['due_date'] ?? '').toString()) ??
                DateTime(9999);
            final db = DateTime.tryParse((b['due_date'] ?? '').toString()) ??
                DateTime(9999);
            return da.compareTo(db);
          });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
              color: AppColors.accent, borderRadius: AppRadius.rPill),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Live project control',
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
        ),
        TextButton(
            onPressed: () => setState(() => _tab = 1),
            child: const Text('View tasks')),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final crew = _pulseMetric(
          icon: Icons.groups_rounded,
          label: 'Crew on site',
          value: '$present/${_workers.length}',
          detail: late > 0 ? '$late late today' : 'Today',
          color: AppColors.green,
          onTap: () => setState(() => _tab = 3),
        );
        final work = _pulseMetric(
          icon: Icons.assignment_turned_in_rounded,
          label: 'Tasks complete',
          value:
              '${tasks.where((task) => _isTaskComplete(task['status'])).length}/${tasks.length}',
          detail: '${remaining.length} remaining',
          color: AppColors.accent,
          onTap: () => setState(() => _tab = 1),
        );
        if (narrow) {
          return Column(children: [crew, const SizedBox(height: 10), work]);
        }
        return Row(children: [
          Expanded(child: crew),
          const SizedBox(width: 10),
          Expanded(child: work),
        ]);
      }),
      const SizedBox(height: 12),
      sectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: AppColors.navyWash, borderRadius: AppRadius.rSm),
              child:
                  Icon(Icons.flag_rounded, size: 16, color: AppColors.navyText),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Upcoming work milestones',
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            TextButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text('All tasks')),
          ]),
          const SizedBox(height: 8),
          if (remaining.isEmpty)
            Text('No outstanding task milestones.',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: AppColors.textMuted))
          else
            ...remaining.take(3).map((task) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.radio_button_unchecked_rounded,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          (task['task_name'] ?? 'Untitled task').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        DateHelper.tryFormatShort(task['due_date'],
                            fallback: 'No date'),
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: AppColors.textMuted)),
                  ]),
                )),
        ]),
      ),
    ]);
  }

  Widget _pulseMetric({
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required Color color,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.rSm),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: AppColors.textMuted)),
                  Text(value,
                      style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                  Text(detail,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textSecondary)),
                ])),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textMuted),
          ]),
        ),
      );

  /// Visual treatment only: the project data, edit action and completion
  /// action stay exactly as before, but the important information now sits on
  /// a construction-image hero with a high-contrast progress panel.
  Widget _projectHero(Map p) {
    final progress =
        (((p['progress'] as num?) ?? 0).toDouble()).clamp(0.0, 100.0);
    final canComplete =
        (p['status'] ?? 'planning') != 'completed' && progress >= 100;
    return Container(
      height: 278,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.rXl,
        boxShadow: AppShadows.md,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/construction_dashboard_hero.png'),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.navyDeeper.withValues(alpha: 0.98),
                  AppColors.navy.withValues(alpha: 0.78),
                  AppColors.navy.withValues(alpha: 0.16),
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                statusPill(p['status'] ?? 'planning'),
                const Spacer(),
                if (canComplete)
                  semanticTapTarget(
                    label: 'Mark project complete',
                    child: GestureDetector(
                      onTap: _markProjectComplete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: AppRadius.rMd,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 15, color: Color(0xFF86EFAC)),
                              SizedBox(width: 5),
                              Text('Complete',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ]),
                      ),
                    ),
                  ),
              ]),
              const Spacer(),
              Text(
                p['project_name'] ?? '-',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 27,
                  height: 1.08,
                  letterSpacing: -0.6,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Row(children: [
                const Icon(Icons.location_on_rounded,
                    size: 17, color: Color(0xFFFBBF24)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    p['location_address'] ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: AppRadius.rMd,
                ),
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppStrings.t('proj.overallCompletion'),
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary)),
                        Text('${progress.toStringAsFixed(0)}%',
                            style: GoogleFonts.inter(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accent)),
                      ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: AppRadius.rMd,
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 9,
                      backgroundColor: AppColors.navyWash,
                      valueColor: AlwaysStoppedAnimation(AppColors.green),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tasksTab() => ListView(padding: const EdgeInsets.all(16), children: [
        // ── Tasks: list + Add New Task ──────────────────────────
        Row(children: [
          Expanded(
            child: Text(AppStrings.t('proj.taskSummary'),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.textPrimary)),
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
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          sectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No tasks yet — tap Add New Task to create one.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textMuted)),
              ),
            ),
          )
        else
          ...tasks.map((t) {
            final name = t['task_name'] ?? '-';
            final status = t['status'] ?? 'todo';
            final priority = t['priority'] ?? 'medium';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: semanticTapTarget(
                  label: (t['task_name'] ?? 'Task').toString(),
                  child: InkWell(
                    borderRadius: AppRadius.rMd,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TaskDetailPage(
                                task: Map<String, dynamic>.from(t))),
                      );
                      if (mounted) _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: AppRadius.rMd,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                    color: AppColors.greenLight,
                                    shape: BoxShape.circle),
                                child: Icon(
                                  status == 'completed'
                                      ? Icons.check_rounded
                                      : Icons.construction_rounded,
                                  size: 16,
                                  color: AppColors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                              ),
                              const SizedBox(width: 8),
                              _priorityChip(priority),
                              const SizedBox(width: 8),
                              statusPill(status),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded,
                                  size: 18, color: AppColors.textMuted),
                            ]),
                            const SizedBox(height: 8),
                            // Second row: due date · assigned worker (single line, never wraps vertically)
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    '${DateHelper.tryFormatShort(t['due_date'], fallback: 'No due date')}  ·  ${t['assigned_workers'] is List && (t['assigned_workers'] as List).isNotEmpty ? '${(t['assigned_workers'] as List).length} worker(s)' : 'Unassigned'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppColors.textMuted),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _quickStatusBtn(
                                    t,
                                    'pending',
                                    Icons.radio_button_unchecked_rounded,
                                    AppColors.yellow),
                                _quickStatusBtn(t, 'in_progress',
                                    Icons.play_arrow_rounded, AppColors.blue),
                                _quickStatusBtn(t, 'completed',
                                    Icons.check_rounded, AppColors.green),
                              ]),
                            ),
                          ]),
                    ),
                  )),
            );
          }),
      ]);

  // ── Workers tab ──
  Widget _workersTab() {
    if (_workers.isEmpty) {
      return _detailEmpty(
          Icons.groups_rounded,
          AppStrings.t('proj.emptyWorkersTitle'),
          AppStrings.t('proj.emptyWorkersDesc'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _workers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (c, i) {
        final Map w = _workers[i] as Map;
        return WorkerListCard(
          worker: w,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkerDetailPage(
                workerId: (w['worker_id'] as num?)?.toInt() ?? 0,
                initial: w,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Attendance tab ──
  Widget _attendanceTab() {
    if (_attendance.isEmpty) {
      return _detailEmpty(
          Icons.fingerprint_rounded,
          AppStrings.t('proj.emptyAttendanceTitle'),
          AppStrings.t('proj.emptyAttendanceDesc'));
    }
    final present =
        _attendance.where((r) => '${r['today_status']}' == 'present').length;
    final late =
        _attendance.where((r) => '${r['today_status']}' == 'late').length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
            child: statCard(
                label: 'On site',
                value: '$present',
                iconColor: AppColors.green)),
        const SizedBox(width: 12),
        Expanded(
            child: statCard(
                label: 'Late', value: '$late', iconColor: AppColors.yellow)),
        const SizedBox(width: 12),
        Expanded(
            child: statCard(
                label: 'Absent',
                value: '${_attendance.length - present - late}',
                iconColor: AppColors.red)),
      ]),
      const SizedBox(height: 16),
      ..._attendance.map((r) {
        final Map row = r as Map;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: WorkerListCard(
            worker: row,
            onTap: () => _openAttendancePhoto(row),
          ),
        );
      }),
    ]);
  }

  Future<void> _openAttendancePhoto(Map row) async {
    final wid = (row['worker_id'] as num?)?.toInt();
    if (wid == null) {
      toast('Invalid worker');
      return;
    }
    try {
      final d = await ApiService().attendanceWorkerToday(wid);
      final url = d?['in_photo_url'] as String?;
      if (url == null || url.isEmpty) {
        toast('No check-in selfie for this worker today');
        return;
      }
      if (!mounted) return;
      showAttendancePhoto(context, url, title: row['name']?.toString());
    } catch (e) {
      toast('Photo unavailable: $e');
    }
  }

  // ── Common tasks tab ──
  static const Map<String, String> _commonKindLabels = {
    'briefing': 'Daily briefing',
    'toolbox': 'Toolbox meeting',
    'housekeeping': 'Housekeeping',
  };

  String _kindLabel(dynamic kind) {
    final k = (kind ?? '').toString().toLowerCase();
    if (k.isEmpty) return 'Common task';
    return _commonKindLabels[k] ?? k.replaceAll('_', ' ');
  }

  bool _isDone(dynamic status) {
    final s = (status ?? '').toString().toLowerCase();
    return s == 'done' || s == 'completed' || s == 'approved';
  }

  Widget _commonTab() {
    final t = AppStrings.t;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('proj.commonTemplates'),
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.textPrimary)),
      const SizedBox(height: 2),
      Text(t('proj.commonTemplatesSub'),
          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
      const SizedBox(height: 12),
      // The three daily jobs are fixed by the spec, so they stay visible even
      // when the endpoint has not seeded today's instances yet.
      ..._commonTemplates().map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _commonTaskTile(c),
          )),
      const SizedBox(height: 16),
      Text(t('proj.commonHistory'),
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      if (_history.isEmpty)
        _emptyCard(t('proj.emptyCommonTitle'), t('proj.emptyCommonDesc'))
      else
        ..._commonHistoryGroups(),
    ]);
  }

  List<Map> _commonTemplates() {
    final live = _common.whereType<Map>().toList();
    if (live.isNotEmpty) return live;
    return const [
      {'task_kind': 'briefing', 'status': 'pending'},
      {'task_kind': 'toolbox', 'status': 'pending'},
      {'task_kind': 'housekeeping', 'status': 'pending'},
    ];
  }

  Widget _commonTaskTile(Map c) {
    final done = _isDone(c['status']);
    return sectionCard(
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: done ? AppColors.greenLight : AppColors.bgMain,
              shape: BoxShape.circle),
          child: Icon(
              done ? Icons.check_rounded : Icons.cleaning_services_rounded,
              size: 17,
              color: done ? AppColors.green : AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_kindLabel(c['task_kind']),
                style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(
                done
                    ? '${c['completed_by_name'] ?? 'Completed'}'
                    : 'Not completed yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        statusPill(done ? 'completed' : 'pending',
            label: done ? 'Done' : 'Pending'),
      ]),
    );
  }

  List<Widget> _commonHistoryGroups() {
    final grouped = <String, List<Map>>{};
    for (final r in _history) {
      final row = (r as Map);
      final key = (row['work_date'] ?? '').toString();
      grouped.putIfAbsent(key, () => <Map>[]).add(row);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) {
      final rows = grouped[k]!;
      final doneCount = rows.where((r) => _isDone(r['status'])).length;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: sectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.event_note_rounded,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(DateHelper.tryFormatShort(k, fallback: k),
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              Text('$doneCount/${rows.length}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            ...rows.map((r) {
              final done = _isDone(r['status']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: done ? AppColors.green : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_kindLabel(r['task_kind']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: AppColors.textPrimary)),
                  ),
                  statusPill(done ? 'completed' : 'pending',
                      label: done ? 'Done' : 'Pending'),
                ]),
              );
            }),
          ]),
        ),
      );
    }).toList();
  }

  // ── Files tab ──
  Widget _filesTab() {
    if (_files.isEmpty) {
      return _detailEmpty(
          Icons.folder_copy_outlined,
          AppStrings.t('proj.emptyFilesTitle'),
          AppStrings.t('proj.emptyFilesDesc'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (c, i) => FileListTile(file: _files[i]),
    );
  }

  // ── Shared empty states ──
  Widget _detailEmpty(IconData icon, String title, String desc) => ListView(
        padding: const EdgeInsets.all(16),
        children: [_emptyCard(title, desc, icon: icon)],
      );

  Widget _emptyCard(String title, String desc, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.rLg,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: AppColors.greenLight, shape: BoxShape.circle),
            child: Icon(icon ?? Icons.info_outline_rounded,
                size: 24, color: AppColors.green),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(desc,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
        ]),
      );

  Future<void> _setTaskStatus(Map t, String newStatus) async {
    final taskId = t['task_id'];
    if (taskId == null) {
      toast('Invalid task');
      return;
    }
    // Completing a task is a forward-only transition (the backend rejects
    // completed -> pending), so require an explicit confirmation and a
    // non-empty completion note (the backend enforces it too).
    if (newStatus == 'completed') {
      final noteCtrl = TextEditingController();
      // Completion evidence captured in the dialog below; kept outside the
      // builder so the preview survives rebuilds.
      CapturedPhoto? photo;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(AppStrings.t('tasks.confirmCompleteTitle')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('tasks.confirmCompleteBody'),
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('tasks.completionNoteLabel'),
                    hintText: AppStrings.t('tasks.completionNoteHint'),
                    border: OutlineInputBorder(borderRadius: AppRadius.rMd),
                  ),
                ),
                const SizedBox(height: 12),
                // The backend rejects completion without a site photo, so it is
                // captured here rather than failing after the dialog closes.
                Row(children: [
                  Icon(
                    photo == null
                        ? Icons.camera_alt_outlined
                        : Icons.check_circle_rounded,
                    size: 18,
                    color:
                        photo == null ? AppColors.textMuted : AppColors.green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      photo == null
                          ? 'Site photo required'
                          : 'Site photo captured',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final shot = await PhotoCapture.takeEvidencePhoto();
                        setLocal(() => photo = shot);
                      } on PhotoCaptureException catch (e) {
                        if (!e.cancelled) toast(e.message);
                      }
                    },
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: Text(photo == null ? 'Take photo' : 'Retake'),
                  ),
                ]),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppStrings.t('common.cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (noteCtrl.text.trim().isEmpty) {
                    toast(AppStrings.t('tasks.completionNoteRequired'));
                    return;
                  }
                  if (photo == null) {
                    toast('Take a site photo to complete this task');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.green),
                child: Text(AppStrings.t('common.confirm')),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      try {
        // Bind to a local so the null-check above is honoured by the analyzer
        // and the two photo fields always describe the same capture.
        final shot = photo!;
        await ApiService().updateTask(taskId, {
          'status': newStatus,
          'completion_note': noteCtrl.text.trim(),
          'photo_base64': shot.base64,
          'photo_mime_type': shot.mimeType,
        });
        t['status'] = newStatus;
        t['completion_note'] = noteCtrl.text.trim();
        toast('Task marked $newStatus');
        TaskStatusNotifier.notify();
        if (mounted) _load();
      } catch (e) {
        toast('Failed to update task: $e');
      }
      return;
    }
    try {
      await ApiService().updateTask(taskId, {'status': newStatus});
      t['status'] = newStatus;
      toast('Task marked $newStatus');
      TaskStatusNotifier.notify();
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
      icon: Icon(icon, size: 18, color: active ? color : AppColors.textMuted),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rMd),
      child: Text(priority,
          style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.textPrimary))),
      ]);
}
