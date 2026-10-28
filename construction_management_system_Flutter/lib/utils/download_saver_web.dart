// ignore_for_file: avoid_web_libraries_in_flutter
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Trigger a browser download for [url] and return an empty path.
///
/// On web there is no filesystem to write to, so the browser owns the download.
/// The anchor gets a `download` attribute so the file lands with its real name
/// instead of the opaque `download` default. `url` is the short-lived signed
/// link, which is the only credential a navigation request can carry.
Future<String> downloadToTemp(String url, String fileName, {String? extensionHint}) async {
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.trim().isEmpty ? 'download' : fileName.trim()
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  // Empty path signals "the browser took over", the caller skips the OS viewer.
  return '';
}

/// No-op on web: the browser already saved the file.
Future<bool> openDownloadedFile(String path) async => false;
