# Mise — Architecture

## Overview

Mise (folder `file_organizer_flutter`) is a Flutter desktop app for Windows and
macOS that organizes a folder into category folders (Images, Documents, Music,
etc.) with optional size/date buckets, name-pattern rules, auto rules, duplicate
detection, rename/date templates, and reversible history. It runs organize jobs
manually, from a system-tray menu, from folder watches, and on schedules, and it
ships a headless CLI (`file_organizer.exe plan|organize|stats`).

Version: `2.2.0+1`. Engine, CLI, and desktop UI share the same core code.

## Layering

```
lib/
  cli.dart                     headless entrypoint (ClIStorage, runCli)
  main.dart                    desktop entrypoint (tray, watcher, scheduler)
  state/
    app_state.dart             composition root + ChangeNotifier (UI state)
    settings_store.dart        persistence seam (shared_preferences JSON)
  services/
    operation_queue.dart       FIFO serialize-all-mutating-work queue
    organize_service.dart      single owner of scan -> plan -> execute -> journal
  core/
    models.dart                HistoryEntry, WatchJob, ScheduleJob, PlannedMove, ...
    rules.dart                 categories, classifyFile, uniqueName, size/date buckets
    organizer.dart             Organizer: scan/execute/trash/undo against a storage
    query.dart                 query parsing + sorting
    suggestion_engine.dart     offline category suggestions from content signatures
    storage/
      storage_service.dart     abstract StorageService
      io_storage_service.dart  real filesystem (with case-insensitive unique names)
      saf_storage_service.dart Android SAF adapter
      unsupported_storage_service.dart  fallback
  ui/
    screens/                   organize, watch, schedule, search, tags, settings, history
    widgets/
test/
  fake_storage.dart            in-memory StorageService used by all unit tests
```

## Architecture decisions

- **Serialized file operations.** All mutating work (organize, undo, trash,
  watch runs, schedule runs) goes through `OperationQueue`. User-initiated runs
  use `wait: true` (queued, FIFO); timer/OS-watcher/scheduler runs use
  `skipIfBusy` so a busy queue never stacks background jobs. This is the
  correctness backstop against concurrent writes.
- **One organize pipeline.** `OrganizeService` owns the scan/plan/execute/trash/
  undo pipeline. `AppState`, the tray, watches, schedules, and the CLI all call
  it; there is no duplicated pipeline logic. It snapshots config into an
  immutable `OrganizeConfig` so a run is stable even if settings change mid-run.
- **Core engine is the asset.** `Organizer`, `rules.dart`, `query.dart`, and the
  models are the tested domain core and are not rewritten; features are layered
  around them.
- **Storage seam.** `StorageService` abstracts the filesystem so the engine is
  testable against `FakeStorage`. `caseInsensitiveNames` is true on Windows/macOS
  so `uniqueName` avoids case-only collisions; it is false on case-sensitive
  filesystems (Android/SAF, other POSIX).
- **Data-loss safety.** `copyFile` never deletes a destination it just wrote;
  on collision it falls back to a unique free path. Undo is journal-driven and
  best-effort.
- **SettingsStore is a persistence seam.** All persistence lives behind
  `SettingsStore`. It is currently one class; a future step may split it into
  per-domain stores (history, watches, schedules, settings, tags) behind a
  facade — nothing else should touch `shared_preferences` directly.

## State model

`AppState` (a `ChangeNotifier`) is the single UI state holder and today also
acts as the composition root. It owns settings, history, watches, schedules,
tags/collections, search, and the tray/watcher/scheduler wiring, and delegates
file work to `OrganizeService` via `OperationQueue`.

Known follow-up: slim `AppState` (currently ~800 lines) by extracting
per-feature controllers (watch, schedule, settings, search, tags) and letting it
be a true composition root. Not a correctness issue — a maintainability one.

## Scheduling

- `ScheduleJob`: interval / daily / weekly recurrence with `nextRun` computed
  locally (see `schedule_test.dart`).
- A single scheduler timer dispatches due jobs through `_runSchedule` with
  `skipIfBusy: true`; a failing job disables itself.
- Watches are polled by a directory watcher that triggers `_runWatch`
  (`skipIfBusy: true`).

## Testing strategy

- **Engine tests** (the bulk): pure Dart unit tests against `FakeStorage` for
  organizer, rules, query, auto rules, suggestion engine, tags, schedules, CLI.
- **Service tests**: `OperationQueue` (FIFO, skipIfBusy, error isolation) and
  `OrganizeService` (scan/execute/trash/undo against `FakeStorage`).
- **No widget tests yet**: screens rely on `AppState` directly. Future: inject
  the state and add widget tests for organize/watch/schedule flows.
- Run: `flutter analyze && flutter test` (94 tests).

## CLI

`cli.dart` implements `plan`, `organize`, and `stats` with a shared flag parser
(`--by-extension/--by-size/--by-date`, `--quiet`, etc.) that tolerates flags
before or after the folder argument. `CliStorage` reports
`caseInsensitiveNames` like the desktop IO storage so behavior matches.

## Non-goals (deferred)

- Web support; Riverpod/Bloc state management; query-DSL rewrite; cloud sync;
  code-signing pipeline (blocked on certificate secrets).