import '../services/app_settings.dart';

/// The four worker skill levels used across the app.
///
/// This mirrors `app/trade_levels.py` on the backend: only these four values
/// are ever sent to the API or stored, the old sixteen fine-grained trades
/// (carpenter / electrical / ...) are retired from the value space. The old
/// values are still *readable* — [TradeLevels.normalise] maps them onto a
/// level so historical records and older cached payloads keep displaying a
/// meaningful label.
class TradeLevel {
  /// Stored value sent to the API (lowercase, exactly as the backend expects).
  final String value;

  /// Labels per UI language: English / 中文 / Bahasa Melayu.
  final String labelEn;
  final String labelZh;
  final String labelMs;

  const TradeLevel({
    required this.value,
    required this.labelEn,
    required this.labelZh,
    required this.labelMs,
  });

  /// Label in the currently selected language (see [AppSettings.lang]).
  String get label => AppSettings.t(labelEn, labelZh, labelMs);
}

class TradeLevels {
  TradeLevels._();

  static const String generalWorker = 'general worker';
  static const String semiSkilledWorker = 'semi skilled worker';
  static const String skilledWorker = 'skilled worker';
  static const String foreman = 'foreman';

  /// Ordered from lowest to highest skill, which is also the order shown in
  /// every dropdown: the list reads like a career ladder for the worker.
  static const List<TradeLevel> all = [
    TradeLevel(
      value: generalWorker,
      labelEn: 'General Worker',
      labelZh: '普工',
      labelMs: 'Pekerja Am',
    ),
    TradeLevel(
      value: semiSkilledWorker,
      labelEn: 'Semi Skilled Worker',
      labelZh: '半熟练工',
      labelMs: 'Pekerja Separa Mahir',
    ),
    TradeLevel(
      value: skilledWorker,
      labelEn: 'Skilled Worker',
      labelZh: '熟练工',
      labelMs: 'Pekerja Mahir',
    ),
    TradeLevel(
      value: foreman,
      labelEn: 'Foreman',
      labelZh: '工头',
      labelMs: 'Mandor',
    ),
  ];

  /// Stored values only, in the same order as [all].
  static List<String> get values => all.map((e) => e.value).toList();

  /// One-line hint under a dropdown so a low-literacy worker understands what
  /// the level means without reading a manual.
  static String hint(String value) {
    switch (value) {
      case generalWorker:
        return AppSettings.t(
          'Helper work: carrying, cleaning, general site support.',
          '杂活：搬运、清理、现场协助。',
          'Kerja bantu: mengangkat, membersih, bantuan tapak.',
        );
      case semiSkilledWorker:
        return AppSettings.t(
          'Finishing work under guidance (drywall, insulation, patching).',
          '在指导下做收尾活（隔墙、保温、修补）。',
          'Kerja kemasan dengan bimbingan (dinding kering, penebat, menampal).',
        );
      case skilledWorker:
        return AppSettings.t(
          'Certified craft work: wiring, piping, formwork, welding.',
          '持证技术活：布线、水管、模板、焊接。',
          'Kerja mahir bertauliah: pendawaian, paip, acuan, kimpalan.',
        );
      case foreman:
        return AppSettings.t(
          'Leads a workfront and checks the work of others.',
          '带领工作面并检查他人工作。',
          'Mengetuai tapak kerja dan memeriksa kerja orang lain.',
        );
      default:
        return '';
    }
  }

  /// Legacy fine-grained trade -> level. Kept in sync with the backend
  /// `MIGRATION_MAP`; used only to render old values that are still in the
  /// database, never to write them back.
  static const Map<String, String> _legacy = {
    'carpenter': skilledWorker,
    'electrical': skilledWorker,
    'electrician': skilledWorker,
    'plumbing': skilledWorker,
    'masonry': skilledWorker,
    'painting': skilledWorker,
    'painter': skilledWorker,
    'welding': skilledWorker,
    'welder': skilledWorker,
    'hvac': skilledWorker,
    'roofing': skilledWorker,
    'roofer': skilledWorker,
    'tiling': skilledWorker,
    'tiler': skilledWorker,
    'glazing': skilledWorker,
    'flooring': skilledWorker,
    'equipment': skilledWorker,
    'steel': skilledWorker,
    'scaffolder': semiSkilledWorker,
    'drywall': semiSkilledWorker,
    'insulation': semiSkilledWorker,
    'laborer': generalWorker,
    'general': generalWorker,
    'supervision': foreman,
  };

  /// Resolve any stored / legacy value to one of the four levels (null when
  /// the value is empty or unrecognised).
  static String? normalise(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw.isEmpty) return null;
    final squeezed = raw.replaceAll(RegExp(r'[-_/\\.,]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (values.contains(squeezed)) return squeezed;
    if (_legacy.containsKey(squeezed)) return _legacy[squeezed];
    for (final prefix in ['pemasang ', 'tukang ', 'pengendali ', 'jurukimpal ']) {
      if (squeezed.startsWith(prefix)) {
        final rest = squeezed.substring(prefix.length).trim();
        if (rest.isEmpty) continue;
        if (values.contains(rest)) return rest;
        if (_legacy.containsKey(rest)) return _legacy[rest];
      }
    }
    return null;
  }

  /// Display label for any stored value: a proper level label when it resolves,
  /// "General Worker" when empty (a worker without a level is a helper by
  /// default), otherwise the raw text so nothing silently turns into "-".
  static String label(String? value) {
    final level = normalise(value);
    if (level == null) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return AppSettings.t('General Worker', '普工', 'Pekerja Am');
      return raw;
    }
    return all.firstWhere((e) => e.value == level).label;
  }

  /// The [TradeLevel] for any stored value, or null when it cannot be resolved.
  static TradeLevel? of(String? value) {
    final level = normalise(value);
    if (level == null) return null;
    return all.firstWhere((e) => e.value == level);
  }
}
