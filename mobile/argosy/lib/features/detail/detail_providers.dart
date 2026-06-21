import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';

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
