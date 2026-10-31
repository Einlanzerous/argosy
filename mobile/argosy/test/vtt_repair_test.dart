import 'package:argosy/features/player/vtt.dart';
import 'package:better_player_plus/better_player_plus.dart';
// The parser the player actually runs; not re-exported by the package barrel.
// ignore: implementation_imports
import 'package:better_player_plus/src/subtitles/better_player_subtitles_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the server's ffmpeg made of Bleach S17E50's end card (ARGY-286): one
/// ASS event with two `\N\N` paragraph breaks, so the cue is followed by two
/// blocks with no timing line — the second of 3+ lines, which is the shape
/// better_player cannot survive.
const _broken = '''WEBVTT

00:02.340 --> 00:11.780
m 442 308 l 1450 308 1450 1028 442 1028

03:21.350 --> 03:23.930
Come with me, Nemuri No. 8!

22:30.000 --> 22:40.000
To defend his family and friends,
he has overcome countless battles.

At the end of that path,
he has become a being
whose power goes beyond boundaries.

Having overcome despair time and time again,
he and his friends
defended the world they live in.

22:41.000 --> 22:42.000
After.
''';

Future<List<dynamic>> _parse(String vtt) =>
    BetterPlayerSubtitlesFactory.parseSubtitles(
      BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.memory,
        content: vtt,
      ),
    );

void main() {
  group('repairVtt', () {
    test('the unrepaired file takes better_player down, not one cue', () {
      // The defect being guarded against: an Error, not an Exception, so the
      // package's own `on Exception` handlers let it through and the whole
      // track is lost. If a better_player upgrade fixes this, this test is
      // the one to delete — repairVtt still keeps the orphaned text.
      expect(_parse(_broken), throwsA(isA<RangeError>()));
    });

    test('a repaired file parses with every cue and every line', () async {
      final subs = await _parse(repairVtt(_broken));
      final texts = subs.map((s) => (s.texts as List<String>).join('\n'));
      expect(subs, hasLength(3)); // the drawing-only cue is gone
      expect(texts, contains('Come with me, Nemuri No. 8!'));
      final card = texts.singleWhere((t) => t.startsWith('To defend'));
      expect(card, contains('whose power goes beyond boundaries.'));
      expect(card, endsWith('defended the world they live in.'));
    });

    test('drops drawing commands but not dialogue that looks like one', () {
      final out = repairVtt('''WEBVTT

00:05.000 --> 00:06.000
m -1.5 2 b 3 4 5 6 7 8
Even without a form,

00:07.000 --> 00:08.000
m 5 people walked in.
''');
      expect(out, isNot(contains('b 3 4')));
      expect(out, contains('00:05.000 --> 00:06.000\nEven without a form,'));
      expect(out, contains('m 5 people walked in.'));
    });

    test('keeps meta blocks, identifiers and cue settings', () {
      final out = repairVtt(
        'WEBVTT\r\n\r\nNOTE hi\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000 line:90%\r\nHello\r\n',
      );
      expect(
        out,
        'WEBVTT\n\nNOTE hi\n\n1\n00:00:01.000 --> 00:00:02.000 line:90%\nHello\n',
      );
    });

    test('composes with shiftVtt, which would otherwise keep the orphans', () {
      final shifted = shiftVtt(repairVtt(_broken), -60);
      expect(shifted, isNot(contains('\n\nAt the end')));
      expect(
        shifted,
        contains('he has overcome countless battles.\nAt the end'),
      );
    });
  });
}
