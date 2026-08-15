/// Checks GitHub Releases for a newer Mise build and compares versions.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const _defaultRepo = 'BezaleelPaul/file_organizer_flutter';

/// A newer release that the user can install.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    required this.notes,
  });

  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String notes;
}

bool _isNewer(String latest, String current) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();
  final l = parts(latest);
  final c = parts(current);
  for (var i = 0; i < 3; i++) {
    final a = i < l.length ? l[i] : 0;
    final b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Fetches the latest GitHub release and returns [UpdateInfo] when a newer
/// version is available, otherwise null (including when offline/unreachable).
Future<UpdateInfo?> checkForUpdates({
  String repo = _defaultRepo,
  required String currentVersion,
}) async {
  try {
    final response = await http
        .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (body['tag_name'] as String?) ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '');
    if (latest.isEmpty) return null;
    if (!_isNewer(latest, currentVersion)) return null;
    return UpdateInfo(
      latestVersion: latest,
      currentVersion: currentVersion,
      releaseUrl: (body['html_url'] as String?) ??
          'https://github.com/$repo/releases/latest',
      notes: (body['body'] as String?) ?? '',
    );
  } catch (_) {
    return null;
  }
}
