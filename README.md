# File Organizer

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
| Sort modes | By extension (default), by size bucket (Small/Medium/Large), by modification date (`YYYY-MM`) |
| Safe | Never overwrites — collisions become `file (1).ext`, `file (2).ext` |
| Undo | Every run writes an `undo_history.json` journal; undo moves everything back and removes created folders |
| Copy mode | Option to copy instead of move (leaves originals in place) |
| History | Review past runs and undo them at any time |
| Watch | Dedicated screen for organizing flows with live progress |
| Dark/light | Follows system theme via Material 3 |

## Screens

- **Dashboard** — overview of the current state and quick actions.
- **Organize** — pick a folder, choose sort mode, preview the plan, run it.
- **Rules** — edit categories and the extensions that map into them.
- **Watch** — live progress while a run executes.
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

Tests cover the classification rules, the unique-name logic, and the organizer
engine against a fake storage backend (`test/`).

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
| `file_organizer-windows.zip` | Windows exe + runtime DLLs |
| `file_organizer-linux.tar.gz` | Linux release bundle |
| `file_organizer-macos.tar.gz` | macOS `.app` bundle |
| `file_organizer-ios.tar.gz` | iOS `.xcarchive` (unsigned; codesign before install) |
| `file_organizer-android.tar.gz` | Android `.aab` + `.apk` |

The workflow uses a build matrix (`windows-latest`, `ubuntu-latest`,
`macos-latest`) with pinned Flutter `3.41.9`, then a `release` job that collects
every artifact into a single GitHub Release with auto-generated release notes.

### Before shipping to stores

The current pipeline produces **unsigned** builds for a quick first release.
Production distribution needs real signing:

- **Android** — replace the debug signing config in
  `android/app/build.gradle.kts` with a keystore. Store the keystore and its
  passwords as GitHub secrets and wire them into the workflow.
- **iOS** — set up an Apple Developer signing certificate + provisioning profile
  as GitHub secrets and remove `--no-codesign`.
- **macOS** — add Developer ID signing and notarization for distribution
  outside the App Store.

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
│   ├── organize_screen.dart
│   ├── rules_screen.dart
│   ├── watch_screen.dart
│   └── history_screen.dart
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
