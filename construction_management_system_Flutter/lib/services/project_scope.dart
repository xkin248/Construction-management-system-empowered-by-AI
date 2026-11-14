import 'package:flutter/foundation.dart';

/// The supervisor's active project scope.
///
/// It intentionally lives above individual pages: selecting a project in the
/// shell must filter Tasks, Workers and Files consistently rather than only
/// changing the label in the top bar.
class ProjectScope {
  ProjectScope._();

  static final ValueNotifier<int?> activeProjectId = ValueNotifier<int?>(null);

  static void select(int? projectId) {
    if (activeProjectId.value != projectId) {
      activeProjectId.value = projectId;
    }
  }
}
