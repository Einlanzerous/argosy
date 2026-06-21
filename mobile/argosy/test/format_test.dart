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
}
