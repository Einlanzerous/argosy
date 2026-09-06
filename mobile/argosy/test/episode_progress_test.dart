// Where a viewer picks up in a run of episodes (ARGY-229). One rule for the
// series screen's Resume button and the season Stow chooser, so "the episode
// you're on" means the same thing in both places.

import 'package:argosy/features/detail/episode_progress.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeSummary _ep(int n, {bool watched = false, double position = 0}) =>
    EpisodeSummary(
      id: 'e$n',
      episodeNumber: n,
      mediaItemId: 'm$n',
      watched: watched,
      positionSeconds: position,
      durationSeconds: 1200,
    );

bool _watched(EpisodeSummary e) => e.watched ?? false;

void main() {
  test('nothing touched means nothing to resume', () {
    expect(resumeIndex([_ep(1), _ep(2)], isWatched: _watched), isNull);
  });

  test('a few seconds in does not count as started', () {
    expect(resumeIndex([_ep(1, position: 3)], isWatched: _watched), isNull);
  });

  test('mid-episode resumes that episode', () {
    final eps = [_ep(1, watched: true), _ep(2, position: 300), _ep(3)];
    expect(resumeIndex(eps, isWatched: _watched), 1);
  });

  test('a finished episode resumes the next one', () {
    final eps = [_ep(1, watched: true), _ep(2, watched: true), _ep(3)];
    expect(resumeIndex(eps, isWatched: _watched), 2);
  });

  test('finishing the last episode lands past the end', () {
    final eps = [_ep(1, watched: true), _ep(2, watched: true)];
    expect(resumeIndex(eps, isWatched: _watched), 2);
  });

  test('the latest episode touched wins over an earlier gap', () {
    final eps = [_ep(1, watched: true), _ep(2), _ep(3, position: 400)];
    expect(resumeIndex(eps, isWatched: _watched), 2);
  });

  test('watched is whatever the caller says it is', () {
    // The series screen overlays optimistic overrides on the server's flag.
    final eps = [_ep(1), _ep(2), _ep(3)];
    expect(resumeIndex(eps, isWatched: (e) => e.episodeNumber == 2), 2);
  });
}
