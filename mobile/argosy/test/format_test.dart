import 'package:argosy/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRuntime', () {
    test('hours and zero-padded minutes', () {
      expect(formatRuntime(2 * 3600 + 4 * 60), '2h 04m');
      expect(formatRuntime(107 * 60), '1h 47m');
    });
    test('minutes only', () => expect(formatRuntime(47 * 60), '47m'));
    test('em-dash for missing or zero', () {
      expect(formatRuntime(null), '—');
      expect(formatRuntime(0), '—');
    });
  });

  group('formatClock', () {
    test('h:mm:ss', () => expect(formatClock(2535), '0:42:15'));
    test('clamps negatives', () => expect(formatClock(-5), '0:00:00'));
  });

  group('formatTitle', () {
    test('humanizes an SxxExx code', () {
      expect(formatTitle('The Good Place s01e01'),
          'The Good Place · Season 1 Ep 1');
    });
    test('leaves a plain title untouched', () {
      expect(formatTitle('Blade Runner'), 'Blade Runner');
    });
    test('empty/null → empty', () {
      expect(formatTitle(null), '');
      expect(formatTitle(''), '');
    });
  });

  group('yearRatingSubtitle', () {
    test('joins year and rating', () {
      expect(yearRatingSubtitle(2024, 8.12), '2024  ·  ★ 8.1');
    });
    test('year only', () => expect(yearRatingSubtitle(1999, null), '1999'));
    test('drops a zero rating', () => expect(yearRatingSubtitle(2000, 0), '2000'));
    test('null when empty', () => expect(yearRatingSubtitle(null, null), isNull));
  });

  group('nowPlayingLabels', () {
    test('a named episode leads with the episode name', () {
      final l = nowPlayingLabels(
        title: 'Futurama s01e02',
        seriesTitle: 'Futurama',
        episodeTitle: 'The Series Has Landed',
        seasonNumber: 1,
        episodeNumber: 2,
      );
      expect(l.title, 'The Series Has Landed');
      expect(l.subtitle, 'Futurama · Season 1, Ep 2');
    });

    test('an unnamed episode leads with the slot, not the filename', () {
      // This is the ARGY-87 symptom: the notification read "Futurama s01e01".
      final l = nowPlayingLabels(
        title: 'Futurama s01e01',
        seriesTitle: 'Futurama',
        episodeTitle: 'Futurama s01e01',
        seasonNumber: 1,
        episodeNumber: 1,
      );
      expect(l.title, 'Season 1, Ep 1');
      expect(l.subtitle, 'Futurama');
    });

    test('the series name is never on both lines', () {
      final l = nowPlayingLabels(
        title: 'Futurama s01e01',
        seriesTitle: 'Futurama',
        seasonNumber: 1,
        episodeNumber: 1,
      );
      expect(l.title, isNot(contains('Futurama')));
      expect(l.subtitle, 'Futurama');
    });

    test('a film keeps its title and year', () {
      final l = nowPlayingLabels(title: 'Blade Runner', year: 1982);
      expect(l.title, 'Blade Runner');
      expect(l.subtitle, '1982');
    });

    test('a film with no year has no second line', () {
      expect(nowPlayingLabels(title: 'Blade Runner').subtitle, isNull);
    });

    test('partial episode metadata falls back to the film shape', () {
      // Season without an episode number can't name a slot.
      final l = nowPlayingLabels(
        title: 'Some Show s01e01',
        seriesTitle: 'Some Show',
        seasonNumber: 1,
      );
      expect(l.title, 'Some Show · Season 1 Ep 1');
    });
  });
}
