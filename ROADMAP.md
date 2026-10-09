# Mise Product & Engineering Roadmap

This document outlines the strategic roadmap for **Mise**, divided into **Track A (Technical Remediation)** to eliminate architectural debt and **Track B (Product Differentiation)** to build uncontested competitive advantages.

---

## Guiding Principle: The One-Sentence Test

> *"Does this make the user less afraid to let Mise touch their files?"*

Every feature and architectural change must reduce friction, uncertainty, or the perceived risk of automated file operations.

---

## Track A: Technical Remediation Plan (Fix Before You Differentiate)

Prerequisite stability and performance engineering before launching new features.

### A1. Fix Duplicate Hashing OOM (Priority: Critical)
- **Problem:** `file.readAsBytes()` buffers entire files into RAM. Large media or archive files cause Out-Of-Memory (OOM) crashes.
- **Solution (3-Stage Cascade):**
  1. **Stage 1 (Size grouping):** Eliminate ~80% of non-duplicates by exact byte length.
  2. **Stage 2 (Signature match):** Compare first 4KB (head) and last 4KB (tail) for files sharing the same size.
  3. **Stage 3 (Streamed Chunked SHA-256):** Stream file chunks via `sha256.bind(file.openRead()).first` so memory consumption remains constant (bounded to ~64KB buffer).
  4. **Large File Guard:** Add `maxHashFileSize` (default: 2GB) to warn or use size+signatures on multi-gigabyte files.

### A2. Move Undo History Out of Target Folders (Priority: High)
- **Problem:** `undo_history.json` placed in target directories pollutes user folders and breaks if folders are moved or cloud-synced.
- **Solution:**
  - Store history in the platform's application support directory via `path_provider` (`getApplicationSupportDirectory()`).
  - Upgrade journal format from flat JSON to SQLite (`sqflite` / `sqflite_common_ffi`) with `operations` and `transactions` tables.
  - Support transactional rollback states (`completed`, `rolled_back`).

### A3. Offload Disk Walking to Background Isolates (Priority: High)
- **Problem:** Synchronous tree traversal and stats on the main isolate can drop frames or freeze the UI on directories with 20,000+ files.
- **Solution:**
  - Wrap recursive disk traversal in background isolates (`Isolate.run` or `Isolate.spawn` with `SendPort` / `ReceivePort`).
  - Stream progress ticks to the UI thread smoothly without blocking animations.

### A4. Decompose `AppState` (Priority: Medium)
- **Problem:** 880-line monolithic `AppState` "God Object" mixes organize, search, storage, watch, and settings state.
- **Solution:**
  - Partition into focused controllers:
    - `OrganizeController` (scan, plan, execute, undo)
    - `SearchController` (index, query, tags, collections)
    - `StorageController` (analytics, duplicates, large files)
    - `WatchController` (watch mode, schedule)
    - `SettingsController` (preferences, theme)
  - Introduce `AppScope` (`InheritedWidget` or provider) for clean dependency injection.

### A5. Expand Local Heuristics Beyond 250-File Cap (Priority: Medium)
- **Problem:** Static 32-keyword dictionary with an arbitrary 250-file limit per scan.
- **Solution:**
  - Remove the 250-file cap and stream classification alongside scanning.
  - Implement a 3-tier intelligence hierarchy:
    1. *Tier 1:* Magic bytes (first 16 bytes).
    2. *Tier 2:* 200+ multi-language filename tokens.
    3. *Tier 3:* On-device quantized ML model (Google Magika via ONNX / `magika_dart`).

---

## Track B: Differentiation Strategy (Where We Win)

### B1. The Uncontested Market Position

| Dimension | Competitors | Mise Advantage |
|:---|:---|:---|
| **Platform Coverage** | Single OS (Hazel = macOS, DropIt = Windows) | **Universal Parity:** Windows, macOS, Linux, Android, iOS, Headless CLI |
| **Data Privacy** | Cloud AI tools upload file contents & metadata | **100% Local & Offline:** Zero telemetry, no API keys, zero network latency |
| **Safety Architecture** | Move-first or basic dry runs | **Plan-First + Atomic Reversible Undo:** Zero data loss guarantee |
| **Disk Hygiene** | Narrow single-purpose sorters | **Holistic Suite:** Sorting, byte duplicate cleaning, deep search, & storage analytics |

### B2. Product Feature Priorities

#### Tier 1 — Build Now (Weeks 1–4)
1. **Selective Smart Undo**: Allow users to undo specific files or sub-folders rather than having to roll back the entire batch.
2. **Duplicate Preview Treemap**: Visually display reclaimable storage space by directory (e.g., "12.4 GB reclaimable in Downloads").
3. **Interactive Drag-to-Reclassify**: Enable manual overrides in the Plan Preview that tune heuristic weights locally.

#### Tier 2 — Build Next (Weeks 5–10)
4. **Natural-Language Rule Input**: Parse prompts like *"Move any PDF with 'invoice' to /Finance and tag 'billing'"* into rule trees.
5. **Mobile "Clean Downloads" Action**: One-tap share-sheet/shortcut flow tailored to mobile storage (APKs, screenshots, WhatsApp media).
6. **Conditional Scheduling**: Run triggers based on state (e.g. *"Run every Sunday at 9 PM, but only if >50 new files exist"*).

#### Tier 3 — Build Later (Weeks 11–16)
7. **Cross-Device Rule Portability**: Export/import rule sets as lightweight JSON bundles.
8. **File Relationship Visualizer**: Graph view clustering files by project, date range, or content affinity.

### B3. Official Positioning Statement

> **Mise is the only file organizer that runs everywhere you do — desktop, mobile, and command line — keeps everything offline, and never lets you lose a file it moved. Scan before you move. Undo anything. Own your data.**

### B4. Non-Goals (What Not to Build)
- ❌ **No cloud file sync** (violates zero-knowledge offline positioning).
- ❌ **No cloud LLM dependencies** (avoids subscription paywalls and confidential data leaks).
- ❌ **No proprietary file formats** (files remain standard OS files).
- ❌ **No native shell extensions** (avoids platform-specific OS hook maintenance).

---

## 16-Week Implementation Timeline

```
Weeks 1-3   [Phase A: Stability]     OOM fix, streamed hashing, isolate traversal, support dir undo
Weeks 4-6   [Phase B: Intelligence]  Magika ONNX integration, cap removal, 3-tier classification
Weeks 7-10  [Phase C: UX Edge]       Selective undo, drag-to-reclassify, natural-language rules
Weeks 11-13 [Phase D: Mobile/Auto]   One-tap mobile action, conditional schedules
Weeks 14-16 [Phase E: Architecture]  AppState decomposition into modular controllers
```
