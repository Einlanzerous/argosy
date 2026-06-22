/// WebVTT cue-timing helper, ported from the web client (`web/src/lib/vtt.ts`)
/// and kept in sync so subtitles line up identically across clients.
///
/// WebVTT cue timestamps are in absolute media time. Under a server-side
/// transcode seek the HLS timeline restarts at `baseOffset`, so the player's
/// position is relative to that offset. [shiftVtt] rewrites the cue timings by
/// `deltaSeconds` (pass `-baseOffset`) so cues align with the relative timeline;
/// cues that end before zero are dropped. Direct play passes delta `0` (no-op).
library;

String shiftVtt(String text, double deltaSeconds) {
  if (deltaSeconds == 0) return text;
  final blocks = text.split(RegExp(r'\n[ \t]*\n'));
  final out = <String>[];
  for (final block in blocks) {
    final lines = block.split('\n');
    final tIdx = lines.indexWhere((l) => l.contains('-->'));
    if (tIdx == -1) {
      out.add(block); // header or note block — leave untouched
      continue;
    }
    final shifted = _shiftTimingLine(lines[tIdx], deltaSeconds);
    if (shifted == null) continue; // cue fell entirely before the seek point
    lines[tIdx] = shifted;
    out.add(lines.join('\n'));
  }
  return out.join('\n\n');
}

String? _shiftTimingLine(String line, double delta) {
  final parts = line.split('-->');
  if (parts.length < 2) return line;
  final rightParts = parts[1].trim().split(RegExp(r'\s+'));
  final start = _parseTs(parts[0].trim()) + delta;
  final end = _parseTs(rightParts[0]) + delta;
  if (end <= 0) return null;
  final settings = rightParts.skip(1).join(' ');
  final head = '${_formatTs(start < 0 ? 0 : start)} --> ${_formatTs(end)}';
  return settings.isNotEmpty ? '$head $settings' : head;
}

double _parseTs(String ts) {
  final dot = ts.split('.');
  final hms = dot[0];
  final ms = dot.length > 1 ? dot[1] : '0';
  var sec = 0.0;
  for (final p in hms.split(':')) {
    sec = sec * 60 + (double.tryParse(p) ?? 0);
  }
  return sec + int.parse(ms.padRight(3, '0').substring(0, 3)) / 1000;
}

String _formatTs(double seconds) {
  final ms = ((seconds - seconds.floor()) * 1000).round();
  var s = seconds.floor();
  final h = s ~/ 3600;
  s -= h * 3600;
  final m = s ~/ 60;
  s -= m * 60;
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(h)}:${p2(m)}:${p2(s)}.${ms.toString().padLeft(3, '0')}';
}
