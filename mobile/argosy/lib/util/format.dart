// Display formatters mirrored from the web client (`web/src/lib/format.ts`),
// kept in sync so the mobile UI reads the same.

/// Runtime like `2h 04m` / `47m` from a duration in seconds.
String formatRuntime(num? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final total = (seconds / 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Clock like `0:42:15` from a position in seconds.
String formatClock(num seconds) {
  final s = seconds < 0 ? 0 : seconds.floor();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

final _episodeCode = RegExp(r'\s*[·\-—]?\s*S(\d{1,2})E(\d{1,2})\b', caseSensitive: false);

/// Humanizes an episode-code title: replaces an `S01E02` token with
/// `Season 1 Ep 2` so cryptic codes don't leak into the UI. Titles without a
/// code are returned untouched.
String formatTitle(String? title) {
  if (title == null || title.isEmpty) return '';
  final m = _episodeCode.firstMatch(title);
  if (m == null) return title;
  final human = 'Season ${int.parse(m.group(1)!)} Ep ${int.parse(m.group(2)!)}';
  final replaced = title.replaceFirst(_episodeCode, ' · $human');
  return replaced.replaceFirst(RegExp(r'^\s*·\s*'), '').trim();
}

/// A poster's secondary line: `2024  ·  ★ 8.1` from a year + rating.
String? yearRatingSubtitle(int? year, num? rating) {
  final parts = <String>[];
  if (year != null) parts.add('$year');
  if (rating != null && rating > 0) parts.add('★ ${rating.toStringAsFixed(1)}');
  return parts.isEmpty ? null : parts.join('  ·  ');
}
