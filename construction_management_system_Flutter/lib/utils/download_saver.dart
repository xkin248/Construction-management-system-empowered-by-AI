/// Platform-neutral "save this download and hand it to the OS" helper.
///
/// The backend download endpoint requires an `Authorization` header, which two
/// client paths cannot supply:
///
///  * Flutter Web, where the browser performs the download navigation and Dio
///    interceptors never run, and
///  * `Image.network` previews, which accept a URL only.
///
/// So the API mints a short-lived signed URL instead (see
/// `ApiService.fetchDownloadLink`) and this helper consumes it: on io platforms
/// it writes the bytes to a temp folder and opens them, on web it triggers the
/// browser download. The conditional export keeps `dart:io` out of the web build
/// and `dart:html` out of the mobile/desktop build.
library;

export 'download_saver_io.dart'
    if (dart.library.html) 'download_saver_web.dart';
