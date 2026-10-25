import 'package:argosy_api/api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../api/api_providers.dart';
import '../../router/app_router.dart';

/// A movie's detail plus its saved play state (for Resume vs Play).
typedef MovieDetailData = ({MediaItemDetail detail, PlayState? progress});

final movieDetailProvider =
    FutureProvider.autoDispose.family<MovieDetailData, String>((ref, id) async {
  final api = ref.watch(libraryApiProvider);
  final detail = await api.getMediaItem(id);
  if (detail == null) throw const ApiFailure('Not found.', statusCode: 404);
  final progress = await api.getProgress(id).then<PlayState?>((p) => p).catchError((_) => null);
  return (detail: detail, progress: progress);
});

final seriesDetailProvider =
    FutureProvider.autoDispose.family<SeriesDetail, String>((ref, id) async {
  final detail = await ref.watch(libraryApiProvider).getSeries(id);
  if (detail == null) throw const ApiFailure('Not found.', statusCode: 404);
  return detail;
});

/// Opens the player over a detail screen and refetches [detail] when it pops
/// (ARGY-266). The detail route stays mounted beneath the full-screen player, so
/// without this its autoDispose provider is never re-read and episodes you just
/// watched keep showing as unwatched.
///
/// The invalidate happens after the player pops, and the screens render with
/// `AsyncView(keepStale: true)`, so the existing content stays up while the
/// refetch runs. Uses the container, not a `WidgetRef`: the screen may have been
/// disposed while the player was open, and the container outlives it.
Future<void> openPlayerThenRefresh(
  BuildContext context,
  ProviderOrFamily detail,
  String itemId, {
  bool resume = false,
  bool startOver = false,
}) async {
  final container = ProviderScope.containerOf(context);
  await openPlayer(context, itemId, resume: resume, startOver: startOver);
  container.invalidate(detail);
}
