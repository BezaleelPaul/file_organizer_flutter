# Mise

Sort files into folders by type, size, or date on any device.

A cross-platform Flutter app that scans a folder and moves (or copies) every file
into categorized subfolders — e.g. `Documents/`, `Images/`, `Videos/`, `Music/`,
`Archives/` — with automatic name de-duplication, an undo history, and optional
size/date buckets.

Targets **Windows**, **Linux**, **macOS**, **Android**, and **iOS**.

---

## Features

| Feature | Description |
|---------|-------------|
| Organize | Scan a folder and move/copy files into category folders |
| Rules | 12 built-in categories (Documents, Images, Videos, Music, Archives, Programs, Scripts, Code, Fonts, CAD, Data, Others) — fully editable |
| Auto rules | Visual builder for multi-condition rules (extensions, name regex, size range, modified window) that route files to any folder |
| Sort modes | By extension (default), by size bucket (Small/Medium/Large), by modification date (`YYYY-MM`) |
| Safe | Never overwrites — collisions become `file (1).ext`, `file (2).ext` |
| Undo | Every run writes an `undo_history.json` journal; undo moves everything back and removes created folders |
| Copy mode | Option to copy instead of move (leaves originals in place) |
| History | Review past runs and undo them at any time |
| Search | Index a folder and search instantly: `report`, `*.pdf`, `type:image`, `>100MB`, `modified:last-week` |
| Tags | Color-coded labels you attach to files; filter with `tag:work` |
| Collections | Save any search as a live, one-tap collection of matching files |
| Storage | See space used per category, byte-identical duplicates (with reclaimable bytes), largest files and empty folders |
| Watch | Dedicated screen for organizing flows with live progress |
| Schedule | Background runs on an interval, daily, or on chosen weekdays (while Mise is running) |
| CLI | Headless `plan` / `organize` / `stats` commands for scripts and cron |
| Tray | System tray icon with hide-to-tray; keeps watched folders organizing in the background |
| Auto-start | Launch Mise at sign-in (Settings) |
| Updates | Checks GitHub Releases and prompts when a new version is available |
| Dark/light | Follows system theme via Material 3 |

## Screens

- **Dashboard** — overview of the current state and quick actions.
- **Search** — instant indexed search with rich queries, plus **Tags** and
  **Smart Collections** (saved searches) tabs.
- **Storage** — deep analysis: category breakdown, duplicates, large files, empty folders.
- **Organize** — pick a folder, choose sort mode, preview the plan, run it.
- **Rules** — edit categories and the extensions that map into them; open the
  visual **Auto rules** builder for multi-condition routing.
- **Watch** — live progress while a run executes, plus a **Schedule** tab for
  interval / daily / weekday background runs.
- **History** — past runs with one-tap undo.

## Platform support

| Platform | Storage backend | Notes |
|----------|-----------------|-------|
| Windows | `dart:io` (`IoStorageService`) | Pick any folder on disk |
| Linux | `dart:io` | Pick any folder on disk |
| macOS | `dart:io` | Pick any folder on disk |
| Android | SAF channel (`SafStorageService`) | Uses the Storage Access Framework to pick a directory |
| iOS | `dart:io` (`IoStorageService`) | Folder picking via the Files app |
| Web | Unsupported (`UnsupportedStorageService`) | Builds, but file operations are disabled |

The backend is chosen automatically by `lib/core/storage/storage_factory.dart`.

---

## Getting started

### Prerequisites

- Flutter SDK **3.41.x** (stable channel), Dart 3.11+
- Platform toolchains for whatever you target:

| Platform | Toolchain |
|----------|-----------|
| Windows | Visual Studio 2022 with the "Desktop development with C++" workload |
| Linux | `clang`, `cmake`, `ninja-build`, `pkg-config`, GTK 3 dev headers |
| macOS | Xcode + CocoaPods |
| Android | Android SDK + JDK 17 |
| iOS | macOS with Xcode |

Check your setup with:

```sh
flutter doctor
```

### Install dependencies

```sh
flutter pub get
```

### Run in development

```sh
flutter run -d windows     # or: -d linux, -d macos, -d android, -d ios
```

---

## Building locally

```sh
# Windows — produces build\windows\x64\runner\Release\file_organizer.exe
flutter build windows --release

# Linux — produces build/linux/x64/release/bundle/
flutter build linux --release

# macOS — produces build/macos/Build/Products/Release/
flutter build macos --release

# Android — produces an AAB (Play Store) and an APK (sideload)
flutter build appbundle --release
flutter build apk --release

# iOS — produces an unsigned Xcode archive
flutter build ipa --release --no-codesign
```

### Testing

```sh
flutter test
```

Tests cover the classification rules, the unique-name logic, the organizer
engine against a fake storage backend, the search query parser, the visual
rule builder, tags/collections, schedule math, and the CLI end-to-end
(`test/`).

---

## Command-line interface

The same engine powers a headless CLI for scripts, cron jobs and CI:

```sh
dart run file_organizer:mise plan <folder>      # preview, no changes
dart run file_organizer:mise organize <folder>  # sort the folder
dart run file_organizer:mise stats <folder>     # per-category totals
```

Common options: `--by-size`, `--by-date`, `--copy`, `--detect-duplicates`,
`--duplicates-to-trash`, `--exclude <regex>` (repeatable), `--rename <template>`,
`--json` for machine-readable output. Settings come from sensible defaults or a
JSON file via `--config`:

```json
{
  "categories": { "Books": [".epub", ".mobi"], "Others": [] },
  "auto_rules": [
    { "name": "Invoice", "category": "Finance",
      "name_pattern": "^invoice", "enabled": true }
  ],
  "exclude_patterns": ["\\.tmp$"]
}
```

---

## Releases (GitHub Actions)

The repository ships a CI workflow (`.github/workflows/release.yml`) that builds
all platforms in the cloud and attaches the installers to a GitHub Release.

### How to release

```sh
git tag v2.0.0
git push origin v2.0.0
```

Pushing any tag matching `v*` triggers the workflow. You can also run it
manually from the **Actions** tab (workflow_dispatch) without a tag.

### Artifacts produced

| Artifact | Contents |
|----------|----------|
| `mise-windows.zip` | Windows exe + runtime DLLs |
| `mise-setup-*.exe` | Windows **installer** (Inno Setup) |
| `mise-linux.tar.gz` | Linux release bundle |
| `mise_*.deb` | Linux Debian package |
| `Mise-*.AppImage` | Linux AppImage |
| `mise-macos.tar.gz` | macOS `.app` bundle |
| `mise-ios.tar.gz` | iOS `.xcarchive` (unsigned; codesign before install) |
| `mise-android.tar.gz` | Android `.aab` + `.apk` |

The workflow uses a build matrix (`windows-latest`, `ubuntu-latest`,
`macos-latest`) with pinned Flutter `3.41.9`, then a `release` job that collects
every artifact into a single GitHub Release with auto-generated release notes.

### Before shipping to stores

The pipeline builds **unsigned** builds for a quick first release, but the
workflow automatically signs when you add these secrets (steps are skipped when
they're absent):

- **Windows** — `WINDOWS_CERT_BASE64` (Base64 PFX) + `WINDOWS_CERT_PASSWORD`
  signs the exe and the installer with `signtool` (removes SmartScreen
  "unknown publisher").
- **macOS** — `MACOS_CERT_BASE64` (Base64 .p12) + `MACOS_CERT_PASSWORD` +
  optional `MACOS_IDENTITY` signs with Developer ID; add `APPLE_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` to also **notarize**.
- **Android** — replace the debug signing config in
  `android/app/build.gradle.kts` with a keystore and wire it into the workflow.
- **iOS** — set up an Apple Developer signing certificate + provisioning profile
  as GitHub secrets and remove `--no-codesign`. **A device cannot install an
  unsigned build at all**, so iOS is blocked until then.

Without signing, macOS is ad-hoc signed and Gatekeeper will show *"cannot be
opened because the developer cannot be verified"* — right-click → **Open** once
(or `xattr -dr com.apple.quarantine file_organizer.app`).

---

## Project structure

```
lib/
├── main.dart                     # Entry point, theme, splash → home switch
├── theme.dart                    # Material 3 light/dark themes
├── core/
│   ├── organizer.dart            # Engine: scan → plan → execute → undo
│   ├── models.dart               # CategoryMap, FileEntry, PlannedMove, HistoryEntry
│   ├── rules.dart                # Classification, size buckets, unique naming
│   ├── disk_scanner.dart         # Recursive scan, duplicates, large/empty, Trash
│   └── storage/
│       ├── storage_service.dart  # Abstract storage interface
│       ├── io_storage_service.dart      # dart:io backend (desktop/iOS)
│       ├── saf_storage_service.dart     # Android Storage Access Framework backend
│       ├── unsupported_storage_service.dart
│       └── storage_factory.dart  # Picks backend per platform
├── state/
│   ├── app_state.dart            # Global app state (ChangeNotifier)
│   └── settings_store.dart       # Persisted settings via shared_preferences
├── screens/
│   ├── home_shell.dart           # Navigation (rail on desktop, bar on mobile)
│   ├── dashboard_screen.dart
│   ├── search_screen.dart
│   ├── storage_screen.dart
│   ├── organize_screen.dart
│   ├── rules_screen.dart
│   ├── auto_rule_screen.dart    # Visual rule builder
│   ├── watch_screen.dart
│   └── history_screen.dart
├── search/
│   ├── query.dart                # Search query parser + matcher
│   └── search_service.dart       # Indexing + on-disk cache
└── widgets/
    ├── common.dart               # Shared widgets
    ├── completion_dialog.dart    # Run-complete dialog
    └── splash_screen.dart
```

### How a run works

1. **Scan** — `Organizer.scan()` lists the folder and computes a category for
   every file without touching anything.
2. **Plan** — the UI shows the planned moves (category, destination subfolder)
   for confirmation.
3. **Execute** — `Organizer.execute()` moves/copies each file, de-duplicating
   names on the fly, and returns a `HistoryEntry` journal.
4. **Undo** — `Organizer.undo()` replays the journal in reverse and prunes the
   folders it created.

## Configuration

| Setting | Location |
|---------|----------|
| App version / build number | `pubspec.yaml` (`version: X.Y.Z+BUILD`) |
| Android application id | `android/app/build.gradle.kts` → `namespace` / `applicationId` |
| iOS / macOS bundle id | `ios/Runner.xcodeproj/project.pbxproj` and `macos/Runner/Configs/AppInfo.xcconfig` |
| Windows app name / icon | `windows/runner/Runner.rc` |

---

## License

See the repository owner for licensing terms.
