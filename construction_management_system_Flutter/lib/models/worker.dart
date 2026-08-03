name: buildsmart
description: AI Construction Management System
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.7.0 <4.0.0'
  flutter: ">=3.38.0"

dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.5.2
  dio: ^5.8.0+1
  intl: ^0.20.2
  geolocator: ^13.0.2
  webview_flutter: ^4.10.0
  webview_flutter_web: ^0.2.3+2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true