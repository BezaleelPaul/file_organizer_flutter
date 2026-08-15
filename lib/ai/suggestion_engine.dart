/// Offline "smart suggestions" for the Organize flow.
///
/// A rule-free heuristic engine that reads a file's name (and a few content
/// bytes) and, when confident, proposes a better destination category than the
/// plain extension rule — e.g. `invoice_2024.dat` → `Documents` even though
/// `.dat` is unclassified. No network, no API key, fully local.
library;

import 'dart:typed_data';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

/// A proposed category override for one file.
class Suggestion {
  const Suggestion({
    required this.fileName,
    required this.fromCategory,
    required this.toCategory,
    required this.confidence,
    required this.reason,
  });

  final String fileName;
  final String fromCategory;
  final String toCategory;

  /// 0.5–1.0: how strongly the engine believes this override is right.
  final double confidence;

  /// Human-readable triggers, e.g. `'invoice' → Documents; PDF content`.
  final String reason;
}

class SuggestionEngine {
  SuggestionEngine({required this.storage, required this.categories});

  final StorageService storage;
  final CategoryMap categories;

  /// Don't read content for more than this many files per scan.
  static const int maxFiles = 250;

  static const Map<String, List<String>> _keywords = {
    'Documents': [
      'invoice', 'receipt', 'report', 'resume', 'cv', 'cover', 'letter',
      'contract', 'agreement', 'memo', 'minutes', 'proposal', 'thesis',
      'essay', 'paper', 'article', 'manual', 'guide', 'notes', 'tender',
      'purchase', 'order', 'quotation', 'warranty', 'insurance', 'claim',
      'statement', 'ledger', 'tax', 'payroll', 'prescription', 'recipe',
      'syllabus', 'transcript',
    ],
    'Images': [
      'photo', 'photograph', 'pic', 'image', 'img', 'picture', 'screenshot',
      'selfie', 'wallpaper', 'render', 'logo', 'icon', 'banner', 'poster',
      'drawing', 'sketch', 'art', 'album', 'portrait', 'scan',
    ],
    'Videos': [
      'video', 'movie', 'film', 'clip', 'trailer', 'episode', 'season',
      'recording', 'webcam', 'cam', 'animation', 'footage', '1080p', '4k',
      's01', 'e01', 'ep1',
    ],
    'Music': [
      'song', 'track', 'remix', 'instrumental', 'music', 'audio', 'ep', 'mix',
      'dj', 'podcast', 'karaoke', 'cover_song',
    ],
    'Archives': [
      'backup', 'archive', 'pack', 'bundle', 'snapshot', 'dump',
    ],
    'Programs': [
      'setup', 'installer', 'install', 'patch', 'update', 'portable',
    ],
    'Scripts': ['automation', 'bot', 'deploy', 'crawl', 'scrape'],
    'Code': ['source', 'module', 'package', 'benchmark', 'test'],
    'Fonts': ['font', 'glyph'],
    'CAD': ['blueprint', 'schematic', 'assembly', 'part'],
    'Data': ['database', 'dataset', 'export', 'timeseries'],
  };

  /// Signature prefixes (as bytes) → category. Only the first 16 bytes of a
  /// file are needed.
  static const List<(String, List<int>)> _magic = [
    ('Documents', [0x25, 0x50, 0x44, 0x46]), // %PDF
    ('Images', [0x89, 0x50, 0x4E, 0x47]), // PNG
    ('Images', [0xFF, 0xD8, 0xFF]), // JPEG
    ('Images', [0x47, 0x49, 0x46, 0x38]), // GIF8
    ('Archives', [0x50, 0x4B, 0x03, 0x04]), // ZIP
    ('Archives', [0x1F, 0x8B]), // gzip
    ('Archives', [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]), // 7z
    ('Music', [0x49, 0x44, 0x33]), // ID3 (MP3)
    ('Music', [0x4F, 0x67, 0x67, 0x53]), // OggS
    ('Videos', [0x1A, 0x45, 0xDF, 0xA3]), // Matroska
    ('Programs', [0x7F, 0x45, 0x4C, 0x46]), // ELF
    ('Programs', [0x4D, 0x5A]), // MZ (PE/DOS)
  ];

  /// Propose category overrides for a scan, capped at [maxFiles] files.
  Future<List<Suggestion>> suggestAll(ScanResult scan) async {
    final out = <Suggestion>[];
    var considered = 0;
    for (final file in scan.files) {
      if (file.skipped) continue;
      if (considered >= maxFiles) break;
      considered += 1;
      final suggestion = await suggestFor(file, scan.root);
      if (suggestion != null) out.add(suggestion);
    }
    return out;
  }

  /// Propose an override for a single planned file, or null when the current
  /// category is already the best guess.
  Future<Suggestion?> suggestFor(PlannedMove file, String root) async {
    final scores = <String, double>{};
    final reasons = <String>[];
    void add(String category, double weight, String reason) {
      scores[category] = (scores[category] ?? 0) + weight;
      reasons.add(reason);
    }

    final ext = extensionOf(file.name);
    final extCategory = _categoryForExtension(ext);
    if (extCategory != null && extCategory != 'Others') {
      add(extCategory, 0.4, '$ext files');
    }

    for (final token in _tokens(file.name)) {
      for (final entry in _keywords.entries) {
        if (entry.value.contains(token)) {
          add(entry.key, 1.0, "'$token'");
        }
      }
    }

    final head = await storage.readHead(root, file.name, 16);
    final magicCategory = head == null ? null : _magicCategory(head);
    if (magicCategory != null) {
      add(magicCategory, 0.8, '${magicCategory.toLowerCase()} content signature');
    }

    if (scores.isEmpty) return null;

    var best = '';
    var bestScore = 0.0;
    var secondScore = 0.0;
    scores.forEach((category, score) {
      if (score > bestScore) {
        secondScore = bestScore;
        best = category;
        bestScore = score;
      } else if (score > secondScore) {
        secondScore = score;
      }
    });

    // Not confident enough, or the current category is already the winner.
    if (bestScore < 0.8) return null;
    if (bestScore - secondScore < 0.6) return null;
    if (best == file.effectiveCategory) return null;

    final confidence =
        secondScore == 0 ? 0.95 : (bestScore / (bestScore + secondScore)).clamp(0.5, 1.0);
    return Suggestion(
      fileName: file.name,
      fromCategory: file.effectiveCategory,
      toCategory: best,
      confidence: confidence,
      reason: reasons.take(2).join('; '),
    );
  }

  String? _categoryForExtension(String ext) {
    if (ext.isEmpty) return null;
    for (final entry in categories.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return null;
  }

  List<String> _tokens(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return stem
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((t) => t.length >= 2)
        .toList();
  }

  String? _magicCategory(Uint8List head) {
    for (final (category, signature) in _magic) {
      if (signature.length <= head.length &&
          _matchesAt(head, signature, 0)) {
        return category;
      }
    }
    return null;
  }

  bool _matchesAt(Uint8List bytes, List<int> signature, int offset) {
    if (offset + signature.length > bytes.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }
}