import 'package:argosy/features/player/vtt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shiftVtt', () {
    const sample = '''WEBVTT

1
00:00:10.000 --> 00:00:12.500
Hello there

2
00:01:00.000 --> 00:01:02.000 line:90%
General Kenobi''';

    test('delta 0 is a no-op (direct play)', () {
      expect(shiftVtt(sample, 0), sample);
    });

    test('shifts every cue back by the base offset', () {
      // baseOffset 30s → pass -30; cues move 30s earlier.
      final out = shiftVtt(sample, -30);
      expect(out, contains('00:00:30.000 --> 00:00:32.000 line:90%'));
      expect(out, contains('General Kenobi'));
      // The header is preserved untouched.
      expect(out, startsWith('WEBVTT'));
    });

    test('preserves cue settings after the timing line', () {
      final out = shiftVtt(sample, -5);
      expect(out, contains('--> 00:00:57.000 line:90%'));
    });

    test('drops cues that end at or before zero', () {
      // Shift by -40s: cue 1 (ends 12.5s) is gone, cue 2 (ends 62s) survives.
      final out = shiftVtt(sample, -40);
      expect(out, isNot(contains('Hello there')));
      expect(out, contains('General Kenobi'));
    });

    test('clamps a cue start to zero when it would go negative', () {
      // Cue 1 starts at 10s; shift -11 → start would be -1, clamped to 0,
      // end 1.5s keeps it alive.
      final out = shiftVtt(sample, -11);
      expect(out, contains('00:00:00.000 --> 00:00:01.500'));
    });
  });
}
