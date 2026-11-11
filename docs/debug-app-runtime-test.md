# Debug Session: app-runtime-test [OPEN]

## Goal
- Test the application end to end and fix any runtime bugs that block normal use.

## Scope
- Backend API
- Flutter web app
- Mounted HTML flows if they are still wired into the app

## Hypotheses
- H1: Some frontend screens still call API routes or payload formats that do not match the backend.
- H2: A few create/update flows succeed in the backend but fail in the UI because returned JSON shapes differ from what the frontend expects.
- H3: Certain pages fail only at runtime due to null handling or type assumptions in Flutter widgets after API data loads.
- H4: Some legacy HTML pages still reference missing endpoints, causing broken flows outside the Flutter UI.
- H5: Authentication or app bootstrap state may break navigation before feature screens finish loading.

## Evidence Plan
- Start the backend and app locally.
- Reproduce major user flows screen by screen.
- Capture concrete runtime errors from browser/dev tools, app logs, and API responses.
- Instrument only the code paths needed to confirm the failing hypothesis before applying a fix.

## Status
- Session opened.
- No business logic modified in this session yet.
- Reproduced a compile-time blocker before app launch.

## Evidence
- `flutter run -d web-server --web-port 3000` fails during compilation.
- Error points to Flutter SDK file `C:\Users\asus\Documents\flutter\packages\flutter\lib\material.dart`.
- Readback of that file shows injected non-Dart content starting around line 138, including notes like `7 个 *_screen.dart` and generated snippets.

## Assessment
- H1-H5 are not yet testable because the app cannot compile.
- New confirmed blocker: the local Flutter SDK is corrupted and must be restored before meaningful app testing can continue.
