# Oyster Homes — Android app

Flutter Android client for the Oyster Homes Sitera ERP. It mirrors the web app's pages, roles and module access, and talks to the same backend API (`https://oyesterhomes.sparkcurv.com/api` by default; changeable on the login screen under "Server settings").

- App name: Oyster Homes
- Package: `com.oysterhomes.sitera`
- Flutter 3.27.1 / Dart 3.6, JDK 17

## Build

```
flutter pub get
flutter analyze
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

The release build is currently signed with the debug key. Set up a release keystore (`android/key.properties`, never committed) before distributing.

## Layout

- `lib/core/` — API client, theme, formatters, file helpers, shared widgets
- `lib/features/<module>/` — one folder per module (dashboard, projects, boq, change_orders, labour, procurement, quotations, inventory, finance, setup)
- `lib/features/shell/` — navigation, search, alerts

See `CLAUDE.md` for the conventions every screen follows.
