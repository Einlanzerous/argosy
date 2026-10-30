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

final _blankLine = RegExp(r'\n[ \t]*\n');
final _drawing = RegExp(
  r'^m(\s+-?\d+(\.\d+)?){2}(\s+([mnlbspc]|-?\d+(\.\d+)?))*$',
);
const _metaPrefixes = ['WEBVTT', 'NOTE', 'STYLE', 'REGION'];

/// Repairs WebVTT the server's ffmpeg conversion can produce from typeset ASS,
/// mirroring `RepairVTT` in `internal/subtitle/vtt.go` (ARGY-286):
///
/// * a block with no timing line — the tail of a cue split off where an ASS
///   `\N\N` paragraph break became a blank line — is joined back onto the cue
///   before it;
/// * lines that are ASS vector-drawing commands (`m 442 308 l …`) are dropped,
///   and a cue left with no text goes with them.
///
/// This matters more here than in a browser: better_player's parser throws a
/// `RangeError` on an untimed block of three or more lines, and since it only
/// catches `Exception` the whole track is lost, not one cue. The server repairs
/// what it converts now; this covers what it converted before, and anything
/// stowed on the device.
String repairVtt(String text) {
  final blocks = <List<String>>[];
  for (final raw in text.replaceAll('\r\n', '\n').split(_blankLine)) {
    final b = raw.replaceAll(RegExp(r'^\n+|\n+$'), '');
    if (b.trim().isEmpty) continue;
    final lines = b.split('\n');
    if (blocks.isEmpty || _isMeta(lines.first) || _hasTiming(lines)) {
      blocks.add(lines);
    } else if (_hasTiming(blocks.last)) {
      blocks.last.addAll(lines); // orphan: the rest of the previous cue
    }
    // Otherwise it is text belonging to no cue; nothing can time it, so drop it.
  }
  final out = <String>[];
  for (final lines in blocks) {
    if (!_hasTiming(lines)) {
      out.add(lines.join('\n'));
      continue;
    }
    final t = lines.indexWhere((l) => l.contains('-->'));
    final kept = lines
        .sublist(t + 1)
        .where((l) => !_drawing.hasMatch(l.trim()));
    if (kept.isEmpty) continue;
    out.add([...lines.sublist(0, t + 1), ...kept].join('\n'));
  }
  return '${out.join('\n\n')}\n';
}

bool _hasTiming(List<String> lines) =>
    lines.take(2).any((l) => l.contains('-->'));

bool _isMeta(String first) => _metaPrefixes.any(
  (p) => first == p || first.startsWith('$p ') || first.startsWith('$p\t'),
);
