import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────
//  GPS helper (same pattern as attendance_geo_helper.dart)
// ─────────────────────────────────────────────
Future<Map<String, double>?> _getSiteGps() async {
  if (kIsWeb) return null;
  try {
    bool svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) return null;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return {'lat': pos.latitude, 'lng': pos.longitude};
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

  void _openProjectForm({Map? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectFormSheet(
        existing: existing,
        onSaved: () {
          _load();
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
        label: const Text('New Project'),
        backgroundColor: AppColors.accent,
      ),
      body: ld
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: projects.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text('No projects yet',
                              style: TextStyle(color: AppColors.textMuted)),
                        ),
                      )
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: projects.length,
                      itemBuilder: (ctx, i) {
                        final p = projects[i];
                        final progress = (p['progress'] as num? ?? 0).toDouble();
                        final workerCount = p['worker_count'] ?? p['tracked_workers'] ?? 0;
                        final radius = (p['fence_radius'] as num? ?? 500).toInt();
                        return sectionCard(
                          margin: const EdgeInsets.only(bottom: 12),
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
                                        child: const Icon(Icons.edit_outlined, size: 14, color: AppColors.textMuted),
                                      ),
                                    ),
                                  ]),
                                ]),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
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
                                      const Icon(Icons.gps_fixed_rounded, size: 11, color: AppColors.green),
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
                                    valueColor: const AlwaysStoppedAnimation(AppColors.green),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text('${progress.toStringAsFixed(0)}% complete',
                                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                                  if (p['end_date'] != null)
                                    Text('Due ${p['end_date']}',
                                        style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
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
  double _radius = 300.0; // meters
  bool _hasGps = false;
  bool _saving = false;
  bool _gpsLoading = false;

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
      _radius = (e['fence_radius'] as num?)?.toDouble() ?? 300.0;
      _hasGps = true;
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
        _gpsLoading = false;
      });
      toast('Site location captured!');
    } else {
      setState(() => _gpsLoading = false);
      toast('Could not get GPS. Please allow location permission.');
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
    if (_name.text.trim().isEmpty) { toast('Project name is required'); return; }
    if (_loc.text.trim().isEmpty)  { toast('Location address is required'); return; }
    if (!_hasGps) { toast('Please capture the site GPS location first'); return; }

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
      toast(_isEdit ? 'Project updated!' : 'Project created!');
      widget.onSaved();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to save project');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime? d) => d == null ? 'Not set'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
      decoration: const BoxDecoration(
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
          Text(_isEdit ? 'Edit Project' : 'New Project',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 20),

          // ── Project Name ──────────────────────────────
          Text('Project Name', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              hintText: 'e.g. Penang Tower Block C',
              hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
              filled: true, fillColor: AppColors.bgMain,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // ── Location Address ──────────────────────────
          Text('Site Address', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _loc,
            decoration: InputDecoration(
              hintText: 'Full address of the construction site',
              hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
              filled: true, fillColor: AppColors.bgMain,
              prefixIcon: const Icon(Icons.place_outlined, color: AppColors.textMuted, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),

          // ── GPS GEOFENCE SECTION ──────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hasGps ? AppColors.greenLight : AppColors.bgMain,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hasGps ? AppColors.green : AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.gps_fixed_rounded, size: 16, color: _hasGps ? AppColors.green : AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Site Geofence',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700,
                          color: _hasGps ? AppColors.green : AppColors.textPrimary)),
                ),
                if (_hasGps)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(8)),
                    child: Text('Set', style: GoogleFonts.outfit(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 10),

              // GPS coordinates display
              if (_hasGps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.location_on, size: 12, color: AppColors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Lat: ${_lat.toStringAsFixed(5)},  Lng: ${_lng.toStringAsFixed(5)}',
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ]),
                ),

              // Get GPS button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _gpsLoading ? null : _getGps,
                  icon: _gpsLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(_hasGps ? 'Re-capture Site Location' : 'Capture Site Location (Go to site first)',
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
                Text('Check-in Radius', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('${_radius.toInt()} m',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
                ),
              ]),
              Slider(
                value: _radius,
                min: 50, max: 2000,
                divisions: 79,
                activeColor: AppColors.accent,
                inactiveColor: AppColors.border,
                onChanged: (v) => setState(() => _radius = v),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('50m (tight)', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text('Workers must be within this distance to check in',
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text('2000m', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Dates ─────────────────────────────────────
          Row(children: [
            Expanded(
              child: _DateButton(
                label: 'Start Date',
                value: _fmtDate(_start),
                onTap: () => _pickDate(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateButton(
                label: 'End Date',
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
                : Text(_isEdit ? 'Save Changes' : 'Create Project',
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
        side: const BorderSide(color: AppColors.border),
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
  Map? _prediction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      final all = await ApiService().getProjects();
      project = all.firstWhere((p) => p['project_id'] == widget.projectId, orElse: () => null);
      tasks = await ApiService().getTasks(widget.projectId);

      // Load AI progress prediction
      try {
        _prediction = await ApiService().getProjectProgressPrediction(widget.projectId);
      } catch (_) {
        _prediction = null;
      }
    } catch (e) {
      toast('Failed to load project: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Scaffold(backgroundColor: AppColors.bgMain, body: Center(child: CircularProgressIndicator()));
    if (project == null) return const Scaffold(backgroundColor: AppColors.bgMain, body: Center(child: Text('Project not found')));
    final p = project!;
    final completed = tasks.where((t) => t['status'] == 'completed').length;
    final radius = (p['fence_radius'] as num?)?.toInt() ?? 500;
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
            label: const Text('Edit'),
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
              statusPill(p['status'] ?? 'planning'),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.place_outlined, size: 13, color: AppColors.textSidebarMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(p['location_address'] ?? '-',
                  style: const TextStyle(color: AppColors.textSidebarMuted, fontSize: 14))),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Overall Completion', style: TextStyle(color: AppColors.textSidebarMuted, fontSize: 13)),
              Text('${p['progress']?.toStringAsFixed(0) ?? 0}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((p['progress'] ?? 0) as num) / 100,
                minHeight: 8, backgroundColor: AppColors.sidebarHover,
                valueColor: const AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── AI Progress Prediction Card ──
        if (_prediction != null) ...[
          _buildAiPredictionCard(),
          const SizedBox(height: 16),
        ],

        // ── Geofence Info Card ────────────────────────
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.greenLight, shape: BoxShape.circle),
                child: const Icon(Icons.gps_fixed_rounded, size: 16, color: AppColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Site Geofence',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                  Text('Workers must be within $radius m to check in',
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
              statusPill('active'),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _infoRow(Icons.radar_rounded, 'Radius', '$radius meters'),
            const SizedBox(height: 8),
            _infoRow(Icons.my_location_rounded, 'Center GPS',
                'Lat ${lat.toStringAsFixed(5)},  Lng ${lng.toStringAsFixed(5)}'),
          ]),
        ),
        const SizedBox(height: 16),

        // Dates
        Row(children: [
          Expanded(child: statCard(label: 'Start', value: p['start_date'] ?? '—')),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Due', value: p['end_date'] ?? '—')),
        ]),
        const SizedBox(height: 16),

        // Tasks
        Text('Task Summary',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: statCard(label: 'Total', value: '${tasks.length}')),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Done', value: '$completed', iconColor: AppColors.green)),
          const SizedBox(width: 10),
          Expanded(child: statCard(label: 'Left', value: '${tasks.length - completed}', iconColor: AppColors.accent)),
        ]),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        Expanded(child: Text(value, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary))),
      ]);

  // ── AI Progress Prediction Card ──
  Widget _buildAiPredictionCard() {
    final pred = _prediction!;
    final trend = pred['trend'] as String? ?? 'on_track';
    final confidence = (pred['confidence'] as num? ?? 70).toDouble();
    final predictedDate = pred['predicted_completion_date'] as String? ?? '-';
    final plannedEnd = pred['planned_end_date'] as String?;
    final insights = pred['ai_insights'] as String? ?? '';
    final milestones = (pred['milestones'] as List?) ?? [];
    final currentProgress = (pred['current_progress'] as num? ?? 0).toDouble();
    final riskFactors = (pred['risk_factors'] as List?)?.cast<String>() ?? [];
    final recommendations = (pred['recommendations'] as List?)?.cast<String>() ?? [];
    final velocity = pred['velocity'] as Map? ?? {};
    final aiUsed = pred['ai_used'] as bool? ?? false;

    final trendColor = switch (trend) {
      'ahead' => AppColors.green,
      'on_track' => AppColors.blue,
      'behind' => AppColors.accent,
      'critical' => AppColors.red,
      _ => AppColors.textMuted,
    };
    final trendLabel = switch (trend) {
      'ahead' => 'Ahead of Schedule',
      'on_track' => 'On Track',
      'behind' => 'Behind Schedule',
      'critical' => 'At Risk — Critical',
      _ => trend,
    };
    final trendIcon = switch (trend) {
      'ahead' => Icons.rocket_launch_rounded,
      'on_track' => Icons.check_circle_rounded,
      'behind' => Icons.warning_rounded,
      'critical' => Icons.error_rounded,
      _ => Icons.help_rounded,
    };

    double predProgress30d = currentProgress;
    for (final m in milestones) {
      if (m['label'] == '30 days') {
        predProgress30d = (m['predicted_progress'] as num).toDouble();
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: trendColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(trendIcon, size: 16, color: trendColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Progress Prediction',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              Row(children: [
                Text(aiUsed ? 'Gemini AI • ' : 'Rule-based • ',
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text('${confidence.toStringAsFixed(0)}% confidence',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.green)),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(trendLabel,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: trendColor)),
          ),
        ]),
        const SizedBox(height: 14),

        // ── AI Insight ──
        if (insights.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(insights,
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, height: 1.45)),
          ),

        // ── Progress Bars ──
        Row(children: [
          _miniStat('Current', '${currentProgress.toStringAsFixed(1)}%', AppColors.textPrimary),
          const SizedBox(width: 8),
          _miniStat('30-Day Pred.', '${predProgress30d.toStringAsFixed(1)}%', trendColor),
          const SizedBox(width: 8),
          _miniStat('Velocity', '${(velocity['weekly_tasks_completed'] ?? 0).toStringAsFixed(1)} /wk', AppColors.textSecondary),
        ]),
        const SizedBox(height: 8),
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: predProgress30d / 100,
                minHeight: 12,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(trendColor.withValues(alpha: 0.2)),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: currentProgress / 100,
                minHeight: 12,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(trendColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Date comparison ──
        Row(children: [
          _datePill('Planned End', plannedEnd ?? '-', AppColors.textSecondary),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted)),
          _datePill('Predicted', _fmtDateStr(predictedDate), trendColor),
        ]),

        // ── Risk factors ──
        if (riskFactors.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Text('Risk Factors', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.red)),
          const SizedBox(height: 6),
          ...riskFactors.take(3).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, size: 14, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary))),
                ]),
              )),
        ],

        // ── Recommendations ──
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('AI Recommendations', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.blue)),
          const SizedBox(height: 6),
          ...recommendations.take(3).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline, size: 14, color: AppColors.blue),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary))),
                ]),
              )),
        ],

        // ── Milestone chips ──
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Text('Predicted Progress Milestones', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: milestones.map((m) {
            final pct = (m['predicted_progress'] as num).toDouble();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.bgMain,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(m['label'] ?? '', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                Text('${pct.toStringAsFixed(0)}%',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: pct >= currentProgress ? AppColors.green : AppColors.red)),
              ]),
            );
          }).toList()),
        ],
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
          Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _datePill(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  String _fmtDateStr(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
