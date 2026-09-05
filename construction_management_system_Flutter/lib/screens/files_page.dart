import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../l10n/app_strings.dart';
import '../models/file.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _loading = true;
  List<FileItem> _files = [];
  List<Map<String, dynamic>> _projects = [];
  int? _selectedProjectId;
  String _selectedCategory = 'all';
  bool _gridMode = true;

  static const _categories = [
    {'value': 'all', 'label': 'All'},
    {'value': 'drawings_photos', 'label': 'Drawings & Photos'},
    {'value': 'documents', 'label': 'Documents'},
    {'value': 'reports', 'label': 'Reports'},
  ];

  static const _catIcons = {
    'all': Icons.all_inbox_rounded,
    'drawings_photos': Icons.folder_shared_rounded,
    'documents': Icons.description_rounded,
    'reports': Icons.assessment_rounded,
  };

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // "Drawings & Photos" is a merged chip backed by two backend categories.
      final cats = _selectedCategory == 'drawings_photos'
          ? const ['drawings', 'photos']
          : <String?>[_selectedCategory];
      final futures = <Future>[
        ProjectCache.get(ApiService()),
        ...cats.map((c) => ApiService().getFiles(
              pid: _selectedProjectId,
              category: c,
            )),
      ];
      final results = await Future.wait(futures);
      _projects = results[0].cast<Map<String, dynamic>>();
      final rawFiles = <dynamic>[
        for (var i = 1; i < results.length; i++) ...results[i] as List,
      ];
      _files = rawFiles
          .map((e) => FileItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      toast('Failed to load files: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteFile(FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppStrings.t('files.deleteTitle'),
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
            'Delete "${file.originalName}"?\nThis moves the file to recycle bin.',
            style: GoogleFonts.outfit(
                fontSize: 13.5, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.t('files.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(AppStrings.t('files.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteFile(file.fileId);
      toast('File deleted');
      _load();
    } catch (e) {
      toast('Delete failed: $e');
    }
  }

  // Maps the merged "Drawings & Photos" chip (and legacy 'all') to a concrete
  // backend category based on the file extension. Images -> photos, everything
  // else picked under Drawings & Photos -> drawings.
  String _resolveUploadCategory(String cat, String name) {
    if (cat != 'drawings_photos' && cat != 'all') return cat;
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    const imageExts = [
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
      'heic', 'heif', 'svg', 'tiff',
    ];
    if (imageExts.contains(ext)) return 'photos';
    return cat == 'drawings_photos' ? 'drawings' : 'documents';
  }

  void _openUpload() {
    int? pid = _selectedProjectId;
    String cat = _selectedCategory == 'all'
        ? 'documents'
        : (_selectedCategory == 'drawings_photos' ? 'drawings_photos' : _selectedCategory);
    String? pickedPath;
    String? pickedName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(AppStrings.t('files.uploadTitle'),
                    style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                // Pick file from system file picker (mobile friendly)
                OutlinedButton.icon(
                  onPressed: () async {
                    final res = await FilePicker.platform.pickFiles();
                    if (res == null || res.files.isEmpty) return;
                    final f = res.files.single;
                    if (f.path == null) {
                      toast('Could not resolve file path');
                      return;
                    }
                    setD(() {
                      pickedPath = f.path;
                      pickedName = f.name;
                      // Infer the concrete category from the file extension
                      // when the merged "Drawings & Photos" or legacy "All"
                      // chip is active, so images land in Photos and drawings
                      // (pdf etc.) land in Drawings.
                      cat = _resolveUploadCategory(cat, f.name);
                    });
                  },
                  icon: Icon(Icons.folder_open_rounded,
                      size: 20, color: AppColors.accent),
                  label: Text(
                    pickedName ?? 'Pick a file...',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: pickedName != null
                            ? AppColors.textPrimary
                            : AppColors.textMuted),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                if (_projects.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: pid,
                    decoration: InputDecoration(
                        labelText: 'Project',
                        prefixIcon: Icon(Icons.apartment_rounded,
                            size: 20, color: AppColors.textMuted)),
                    items: [
                      DropdownMenuItem<int>(
                          value: null,
                          child: Text(AppStrings.t('files.noProject'))),
                      ..._projects.map((p) => DropdownMenuItem<int>(
                          value: p['project_id'],
                          child: Text(p['project_name'] ?? ''))),
                    ],
                    onChanged: (v) => setD(() => pid = v),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(cat),
                  initialValue: cat,
                  decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_rounded,
                          size: 20, color: AppColors.textMuted)),
                  items: _categories
                      .where((c) => c['value'] != 'all')
                      .map((c) => DropdownMenuItem<String>(
                          value: c['value'],
                          child: Text(c['label']!)))
                      .toList(),
                  onChanged: (v) => setD(() => cat = v!),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    // Mandatory: file + project + category.
                    if (pickedPath == null || pickedPath!.isEmpty) {
                      toast('Please pick a file first');
                      return;
                    }
                    if (pid == null || pid! <= 0) {
                      toast('Please select a project');
                      return;
                    }
                    if (cat.isEmpty || cat == 'all') {
                      toast('Please select a category');
                      return;
                    }
                    try {
                      await ApiService().uploadFile(File(pickedPath!),
                          pid: pid, category: _resolveUploadCategory(cat, pickedName ?? ''));
                      if (ctx.mounted) Navigator.pop(ctx);
                      toast('File uploaded!');
                      _load();
                    } on DioException catch (e) {
                      toast(e.message ?? 'Upload failed');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(AppStrings.t('files.upload')),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _openPreview(FileItem file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(file.originalName,
                style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            if (file.isImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  ApiService().downloadUrl(file.fileId),
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, prog) => prog == null
                      ? child
                      : Container(
                          height: 220,
                          color: AppColors.bgMain,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                  errorBuilder: (_, __, ___) => Container(
                    height: 220,
                    color: AppColors.bgMain,
                    child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 40, color: AppColors.textMuted)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _detailRow('Type', file.mimeType),
            _detailRow('Category', file.categoryLabel),
            _detailRow('Size', file.sizeFormatted),
            _detailRow('Date', file.dateFormatted),
            if (file.uploadedByName != null)
              _detailRow('Uploaded by', file.uploadedByName!),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  final url = ApiService().downloadUrl(file.fileId);
                  _launchDownload(url, file.originalName);
                },
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(AppStrings.t('files.downloadOpen')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.outfit(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ]),
      );

  void _launchDownload(String url, String fileName) async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/buildsmart');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final savePath = '${dir.path}/$fileName';
      await Dio().download(url, savePath);
      if (Platform.isWindows) {
        await Process.run('start', [savePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [savePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [savePath]);
      } else {
        toast('Saved to: $savePath');
        return;
      }
      toast('Opened: $fileName');
    } catch (e) {
      toast('Could not open file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      floatingActionButton: SizedBox(
        width: 56,
        height: 56,
        child: FloatingActionButton(
          onPressed: _openUpload,
          backgroundColor: AppColors.accent,
          child: const Icon(Icons.upload_file_rounded, color: Colors.white),
        ),
      ),
      body: Column(children: [
        // ── Project dropdown ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedProjectId,
                    isExpanded: true,
                    icon: Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.expand_more_rounded,
                          color: AppColors.textSecondary),
                    ),
                    style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                    hint: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(AppStrings.t('files.allProjects'),
                          style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              color: AppColors.textMuted)),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                          value: null,
                          child: Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(AppStrings.t('files.allProjects')),
                          )),
                      ..._projects.map((p) => DropdownMenuItem<int?>(
                          value: p['project_id'],
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(p['project_name'] ?? ''),
                          ))),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedProjectId = v);
                      _load();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // ── Grid/List toggle ──
            SizedBox(
              width: 48,
              height: 48,
              child: Material(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _gridMode = !_gridMode),
                  child: Icon(
                    _gridMode
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ]),
        ),
        // ── Category filter chips ──
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final cat = _categories[i];
              final selected = _selectedCategory == cat['value'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedCategory = cat['value']!);
                  _load();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _catIcons[cat['value']] ?? Icons.folder_rounded,
                      size: 17,
                      color: selected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat['label']!,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // ── File list / grid ──
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _files.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _gridMode ? _buildGrid() : _buildList(),
                    ),
        ),
      ]),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.folder_open_rounded,
                    size: 34, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text(AppStrings.t('files.noFiles'),
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Tap + to upload construction files,\ndrawings, photos, or reports.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _buildGrid() => LayoutBuilder(builder: (ctx, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        final cardWidth =
            (constraints.maxWidth - 32 - (crossAxisCount - 1) * 10) /
                crossAxisCount;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cardWidth / (cardWidth * 0.95),
          ),
          itemCount: _files.length,
          itemBuilder: (ctx, i) => _fileCard(_files[i]),
        );
      });

  Widget _buildList() => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        itemCount: _files.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _fileListTile(_files[i]),
        ),
      );

  // ── Grid card ──
  Widget _fileCard(FileItem file) {
    return GestureDetector(
      onTap: () => _openPreview(file),
      onLongPress: () => _deleteFile(file),
      child: sectionCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _catBgColor(file.fileCategory),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: file.isImage && file.thumbnailPath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            ApiService().downloadUrl(file.fileId),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) =>
                                _fileIcon(file),
                          ),
                        )
                      : _fileIcon(file),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              file.originalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              '${file.sizeFormatted}  ${file.dateFormatted}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                  fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── List tile ──
  Widget _fileListTile(FileItem file) {
    return GestureDetector(
      onTap: () => _openPreview(file),
      onLongPress: () => _deleteFile(file),
      child: sectionCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _catBgColor(file.fileCategory),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: _fileIcon(file, size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Row(children: [
                  _infoChip(file.categoryLabel),
                  const SizedBox(width: 8),
                  Text(file.sizeFormatted,
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  Text(file.dateFormatted,
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppColors.textMuted)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }

  Widget _fileIcon(FileItem file, {double size = 32}) {
    IconData icon;
    Color color;
    if (file.isImage) {
      icon = Icons.image_rounded;
      color = AppColors.purple;
    } else if (file.isPDF) {
      icon = Icons.picture_as_pdf_rounded;
      color = AppColors.red;
    } else {
      switch (file.fileCategory) {
        case 'drawings':
          icon = Icons.architecture_rounded;
          color = AppColors.blue;
          break;
        case 'reports':
          icon = Icons.assessment_rounded;
          color = AppColors.green;
          break;
        default:
          icon = Icons.description_rounded;
          color = AppColors.accent;
      }
    }
    return Icon(icon, size: size, color: color);
  }

  Widget _infoChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.bgMain,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label,
            style: GoogleFonts.outfit(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Color _catBgColor(String cat) {
    switch (cat) {
      case 'drawings':
        return AppColors.blueLight;
      case 'photos':
        return AppColors.purpleLight;
      case 'reports':
        return AppColors.greenLight;
      default:
        return AppColors.accentLight;
    }
  }
}
