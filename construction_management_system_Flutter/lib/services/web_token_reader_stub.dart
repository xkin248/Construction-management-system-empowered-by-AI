// Stub used on every platform except web. dart:html isn't available on
// Android/iOS/desktop, so this always returns null there — the native
// FlutterBridge JS-channel path in main.dart handles those platforms instead.
String? readWebToken() => null;
