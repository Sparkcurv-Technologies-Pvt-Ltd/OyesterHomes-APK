# Oyster Homes — Sitera ERP Android app (Flutter)

Native Android client for the Oyster Homes Sitera ERP. It is a one-to-one port of the web frontend in
`../OyesterHomes-Sitera/frontend` onto the same FastAPI backend (`../OyesterHomes-Sitera/backend`, every call under `/api`).
App name "Oyster Homes", package `com.oysterhomes.sitera`, default server `https://oyesterhomes.sparkcurv.com` (changeable on the login screen).

## Hard rules
- Never change anything in `../OyesterHomes-Sitera` (backend, frontend, roles, business logic). Read it; never write to it.
- Never start or probe servers (no curl, no uvicorn, no yarn start).
- Parity with the web: same endpoints, same payload fields, same role and module gates, same validations and wording.
  Read the web page/component AND the backend router for real field names; never guess.
- Auth is the Bearer token from `POST /auth/login` (`access_token`); the backend accepts it in place of its cookie.
- Flutter 3.27.1 / Dart 3.6: `DropdownButtonFormField` takes `value:` (not `initialValue:`); use `withValues(alpha:)`, not `withOpacity`;
  `setState` callbacks must not return a Future; `CardTheme`/`DialogTheme`/`TabBarTheme` (not `*ThemeData`).

## Structure
- `lib/core/` — shared, do not fork: `network/api_client.dart` (get/post/put/patch/delete return decoded JSON; `upload`, `download`),
  `theme/` (`context.pal` palette, `tabular()`, `Radii`, `monoFamily`), `utils/formatters.dart` (`inr`, `inrCompact`, `qty`, `toNum`,
  `fmtDate` dd/mm/yyyy, `fmtDateTime`, `isoDay`, `todayIso`, `humanize`, `dash`), `utils/files.dart` (`pickAndUpload`, `openServerFile`,
  `downloadAndOpen`, `downloadAndShare`, `openExternal`, `shareText`), `widgets/common.dart` (Surface, Eyebrow, SectionHeader, InfoTile,
  KeyValueRow, StatusChip/statusTone, CodeTag, KpiTile, KpiGrid, LevelBar, MoneyText, LoadingView, EmptyState, ErrorRetry, AsyncView,
  RefreshList, showToast, runAction, confirmDialog, promptText, showAppSheet, SubmitButton, AppTextField, AppDropdown, DateField,
  ChoiceRow, FilterBar, SearchField, SwitchRow, RowTile, RowGroup, TotalBand, InitialsAvatar, AppScaffold).
- `lib/features/auth/` — `AuthProvider` (`context.watch<AuthProvider>().user` is an `AppUser`: `role`, `roleIn([...])` exact like the web's
  `roles.includes`, `hasRole([...])` backend-style (SuperAdmin passes, ProjectManager passes where SiteEngineer does), `hasModule(key)`,
  `canWrite`, `isAdmin`, `id`).
- `lib/features/org/org_provider.dart` — company/branch slice: `org.orgParams` for list/dashboard calls, `org.orgKey` as AsyncView `depKey`.
- `lib/features/shell/` — app frame, nav (`nav_config.dart` = web GEARS), `routes.dart` (`push(context, screen)`, `openWebPath(context, '/admin/...')`).
- `lib/features/<module>/` — one folder per module. Public screens keep the class names/constructors listed in each file's doc comment.

## Screen conventions
- Top-level pages (drawer/bottom bar) return a `Scaffold` with NO AppBar (the shell draws it); they may have a FAB.
- Pushed screens use `AppScaffold(title:, subtitle:, actions:, body:, fab:)`. Project tabs are embedded widgets (no Scaffold), scrollable themselves.
- The web's tables become `RowGroup` lists of `RowTile`s (figures right-aligned with `tabular`); its Dialogs become `showAppSheet` bottom sheets;
  its Tabs become a `TabBar(isScrollable: true)`; `window.confirm` → `confirmDialog`; `window.prompt` → `promptText`; sonner → `showToast`.
- Every screen: loading, empty, error-with-retry (AsyncView does this), pull-to-refresh on lists, success toast after writes.
- Money with `inr()`, dates with `fmtDate()`, statuses with `StatusChip`. Colour carries state only.
- Touch targets ≥ 48dp; forms in sheets with correct keyboard types.

## Build (Windows, Git Bash)
```
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot"
flutter analyze
flutter build apk --debug      # or --release (signed with the debug key until a release keystore is set up)
```
