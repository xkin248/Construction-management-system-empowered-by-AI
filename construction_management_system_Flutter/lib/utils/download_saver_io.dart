import 'dart:io';

import 'package:dio/dio.dart';

/// Download [url] into a per-app temp folder and return the saved path.
///
/// [url] is a short-lived signed link, so no `Authorization` header is needed
/// and none is sent: this is the same request shape the browser uses on web,
/// which keeps the two platform paths behaviourally identical.
///
/// The file name comes from the server-side `original_name`, which may contain
/// characters that are illegal on Windows, hence the sanitiser.
Future<String> downloadToTemp(String url, String fileName, {String? extensionHint}) async {
  final safeName = _sanitizeName(fileName, extensionHint);
  final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}buildsmart');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final savePath = '${dir.path}${Platform.pathSeparator}$safeName';
  await Dio().download(url, savePath);
  return savePath;
}

/// Hand a downloaded file to the OS default application.
///
/// Returns true when a viewer was launched; false when the platform has no
/// generic "open" command (the caller then just reports the saved path).
Future<bool> openDownloadedFile(String path) async {
  if (Platform.isWindows) {
    await Process.run('start', [path], runInShell: true);
    return true;
  }
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
    return true;
  }
  if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
    return true;
  }
  // Android / iOS: there is no portable "open with" call, so the caller falls
  // back to telling the user where the file landed.
  return false;
}

String _sanitizeName(String fileName, String? extensionHint) {
  var name = fileName.trim();
  if (name.isEmpty) name = 'download';
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (extensionHint != null &&
      extensionHint.isNotEmpty &&
      !name.toLowerCase().endsWith('.${extensionHint.toLowerCase()}')) {
    name = '$name.$extensionHint';
  }
  return name;
}
