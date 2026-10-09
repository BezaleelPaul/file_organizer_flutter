<p align="center">
  <img src="assets/banner.png" alt="Mise Banner" width="100%">
</p>

<p align="center">
  <strong>Your files. Finally organized.</strong><br>
  <em>A local-first, safety-guaranteed file organizer and disk intelligence suite for desktop, mobile, and terminal.</em>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.41.x-02569B?logo=flutter" alt="Flutter"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart" alt="Dart"></a>
  <img src="https://img.shields.io/badge/Tests-94%20Passing-brightgreen" alt="Tests">
  <img src="https://img.shields.io/badge/Platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-informational" alt="Platforms">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
</p>

---

## The Mise Philosophy

> **Mise is the only file organizer that runs everywhere you do — desktop, mobile, and command line — keeps everything 100% offline, and never lets you lose a file it moved. Scan before you move. Undo anything. Own your data.**

Named after the French culinary discipline *mise en place* (*"everything in its place"*), Mise replaces messy single-platform scripts, paid proprietary utilities, and cloud-dependent file sorters with an offline, high-performance workstation.

---

## Highlights & What's New

<table>
  <tr>
    <td width="50%">
      <h3>🛡️ "Zero Fear" Safety Architecture</h3>
      <ul>
        <li><strong>Interactive Plan Preview:</strong> See exactly where every file goes before moving a single byte.</li>
        <li><strong>Collision-Proof Renaming:</strong> Never overwrites existing files — automatically sequences collisions as <code>file (1).ext</code>.</li>
        <li><strong>Selective Smart Undo:</strong> Revert an entire batch or <strong>roll back single specific files</strong> without reverting the whole run.</li>
        <li><strong>Centralized OS Journals:</strong> History is preserved in the OS Application Support directory (<code>%APPDATA%</code>, <code>~/Library</code>) — keeping target folders completely clean.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>⚡ High-Performance Disk Engine</h3>
      <ul>
        <li><strong>Streamed 3-Stage Duplicate Finder:</strong> OOM-proof memory management that streams files in 64KB chunks — handles 50GB+ files without RAM spikes.</li>
        <li><strong>Reclaimable Storage Treemap:</strong> Visual breakdown of duplicate disk waste by category with a 1-click <em>"Clean Duplicates"</em> action.</li>
        <li><strong>Background Isolate Traversal:</strong> Recursive folder walking runs in dedicated Dart isolates — keeps UI butter-smooth at 60/120fps.</li>
        <li><strong>Deep Search & Tags:</strong> Rich query syntax (<code>type:image</code>, <code>>100MB</code>, <code>modified:last-week</code>) and color-coded virtual tags.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>🧠 Adaptive Local Intelligence</h3>
      <ul>
        <li><strong>100% Private & Offline:</strong> Zero cloud telemetry, no OpenAI API keys, and zero external network calls.</li>
        <li><strong>Magic Byte Verification:</strong> Reads file signatures (PDF, PNG, MP3, WebP, FLAC, SQLite, ELF, PE) to classify files even when extensions are missing or misleading.</li>
        <li><strong>Self-Tuning Heuristics:</strong> Remembers your manual overrides in the Plan Preview to automatically train future classifications.</li>
        <li><strong>No File Limits:</strong> Analyzes thousands of files progressively with streaming classification.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>💻 Desktop, Mobile & CLI Parity</h3>
      <ul>
        <li><strong>Material 3 Interface:</strong> Adaptive layout supporting desktop navigation rails, light/dark modes, and mobile navigation bars.</li>
        <li><strong>System Tray Daemon:</strong> Background folder watching and instant tray-driven organization.</li>
        <li><strong>Headless CLI (<code>mise</code>):</strong> Native command-line interface for bash scripts, cron jobs, and CI automation with JSON output.</li>
        <li><strong>Universal Storage Layer:</strong> Bridges <code>dart:io</code> and Android's Storage Access Framework (SAF) seamlessly.</li>
      </ul>
    </td>
  </tr>
</table>

---

## Application Screens

| Screen | Description |
|---|---|
| **Dashboard** | Instant overview of organized files, recent runs, watched folders, and quick-start actions. |
| **Organize** | Pick any folder, choose sort mode (Extensions, Size, Date, or Rules), review the interactive plan, reclassify on the fly, and execute safely. |
| **Storage Center** | Disk space breakdown, large file finder, empty folder cleanup, and the **Duplicate Treemap** with reclaimable space analytics. |
| **Search & Tags** | Fast indexed search with rich query operators (<code>type:image</code>, <code>tag:work</code>, <code>>50MB</code>) and dynamic Smart Collections. |
| **Rules & Auto Rules**| 12 customizable category maps plus a visual multi-condition rule builder (Regex names, size ranges, extensions, date windows). |
| **Watch & Schedule** | Background directory monitoring with debounce timers, recurring interval schedules, and tray synchronization. |
| **History** | Audit trail of all previous runs with complete batch rollback and **per-file selective undo**. |

---

## How a Run Works

```mermaid
flowchart LR
    A["1. Scan Folder"] --> B["2. Review Plan"]
    B --> C["3. Execute Moves"]
    C --> D["4. Centralized Journal"]
    D --> E["5. Selective / Batch Undo"]
    
    style A fill:#1e293b,stroke:#3b82f6,stroke-width:2px,color:#fff
    style B fill:#1e293b,stroke:#6366f1,stroke-width:2px,color:#fff
    style C fill:#1e293b,stroke:#10b981,stroke-width:2px,color:#fff
    style D fill:#1e293b,stroke:#f59e0b,stroke-width:2px,color:#fff
    style E fill:#1e293b,stroke:#ec4899,stroke-width:2px,color:#fff
```

1. **Scan** — `Organizer.scan()` categorizes files using extensions, visual rules, and magic bytes without modifying anything on disk.
2. **Plan** — Mise presents a review table showing source, target folder, and suggestions. Users can reclassify or skip files.
3. **Execute** — Files are moved or copied. Colliding filenames automatically get unique numerical suffixes (`photo (1).jpg`).
4. **Journal** — Every operation is recorded in the OS Application Support directory (`history.json`).
5. **Undo** — At any time, users can revert individual files or rollback the entire batch to restore originals and remove empty folders.

---

## Command-Line Interface (CLI)

The exact same Dart engine powers a headless CLI executable:

```bash
# Preview planned moves without touching disk
dart run file_organizer:mise plan /path/to/folder

# Organize folder by extension
dart run file_organizer:mise organize /path/to/folder

# Sort by date buckets into YYYY-MM subfolders
dart run file_organizer:mise organize /path/to/folder --by-date

# Detect byte duplicates and move redundancies to Trash
dart run file_organizer:mise organize /path/to/folder --detect-duplicates --duplicates-to-trash

# Output machine-readable JSON for scripts and CI
dart run file_organizer:mise stats /path/to/folder --json
```

---

## Competitive Comparison

| Feature | **Mise** | **Hazel** | **File Juggler** | **DropIt** | **Python `organize`** |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Platforms** | **Windows, macOS, Linux, Android, iOS** | macOS only | Windows only | Windows only | Cross-platform (CLI) |
| **Price** | **Free / Open Source** | $42+ | $40 | Free | Free |
| **Interface** | **Material 3 GUI + Tray + CLI** | Preferences pane | Legacy Win32 | Floating box | YAML / Terminal only |
| **Undo Safety** | **Selective + Batch Undo** | Basic Trash | Basic Trash | Limited | Dry-run only |
| **Duplicate Engine** | **3-Stage Streamed SHA-256 + Treemap** | None | None | None | Basic |
| **Intelligence** | **Local Magic Bytes + Self-Tuning Tokens** | PDF text matching | Content rules | Pattern matching | Regex filters |
| **Memory Footprint** | **Constant 64KB bounded stream** | Low | Medium | Low | Medium |

---

## Installation & Getting Started

### Prerequisites
- Flutter SDK **3.41.x+**, Dart SDK **3.11+**
- Platform toolchains (Visual Studio C++ for Windows, Xcode for macOS/iOS, GTK headers for Linux).

### Setup & Run
```bash
# Clone the repository
git clone https://github.com/BezaleelPaul/file_organizer_flutter.git
cd file_organizer_flutter

# Install dependencies
flutter pub get

# Run the test suite
flutter test

# Launch on your platform
flutter run -d windows    # or: -d macos, -d linux, -d android
```

### Release Builds
```bash
# Windows Installer / Executable
flutter build windows --release

# macOS Application Bundle
flutter build macos --release

# Linux Package
flutter build linux --release

# Android APK & App Bundle
flutter build apk --release
flutter build appbundle --release
```

---

## Roadmap

See the detailed **[ROADMAP.md](ROADMAP.md)** for the complete two-track plan:
- **Track A (Technical Remediation)**: All stability, memory, and architectural tasks complete.
- **Track B (Product Differentiation)**: Selective undo and duplicate treemaps delivered; natural language rule grammar and Magika ONNX neural runtime in progress.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
