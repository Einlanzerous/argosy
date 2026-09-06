import 'package:argosy_api/api.dart';

/// Where a viewer picks up in an ordered run of episodes.
///
/// The index of the last episode left mid-way, else the one after the last
/// episode finished. Null when nothing has been touched. Can equal
/// `episodes.length` — the last episode touched was the final one and it was
/// finished — so callers treat that as "past the end" rather than indexing.
///
/// Shared by the series screen's Resume button (over the whole series) and the
/// season Stow chooser (over one season), so "where you are" means the same
/// thing in both places (ARGY-229).
int? resumeIndex(
  List<EpisodeSummary> episodes, {
  required bool Function(EpisodeSummary) isWatched,
}) {
  var lastTouched = -1;
  for (var i = 0; i < episodes.length; i++) {
    if (_touched(episodes[i], isWatched)) lastTouched = i;
  }
  if (lastTouched == -1) return null;
  final last = episodes[lastTouched];
  if (!isWatched(last) && (last.positionSeconds ?? 0) > 5) {
    return lastTouched; // still mid-episode
  }
  return lastTouched + 1;
}

/// Watched, or more than a few seconds in — a tap that was closed straight
/// away shouldn't count as having started something.
bool _touched(EpisodeSummary e, bool Function(EpisodeSummary) isWatched) =>
    isWatched(e) || (e.positionSeconds ?? 0) > 5;
