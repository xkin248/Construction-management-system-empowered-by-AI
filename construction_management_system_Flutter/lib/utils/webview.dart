// 编译时按平台选实现：Web → stub；Android/iOS → 真实 webview_flutter
export 'webview_stub.dart'
    if (dart.library.io) 'webview_native.dart';