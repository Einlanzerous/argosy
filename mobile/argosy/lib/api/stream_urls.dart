/// Builds fully-qualified URLs for the endpoints that authenticate via a
/// `?token=` query param instead of a Bearer header.
///
/// These are consumed by clients that can't set HTTP headers — the video
/// player (direct-play + HLS transcode artifacts), the `<track>`-style sidecar
/// subtitle fetch, and the Beacon SSE `EventSource`. They deliberately do NOT
/// go through the generated API client; they're raw URLs handed to those
/// players/streams. See the server backbone notes (mirrors `/stream?token=`).
class StreamUrls {
  StreamUrls(this._baseUrl, [this._token]);

  final String _baseUrl;
  final String? _token;

  /// Direct-play stream for an item.
  Uri streamItem(String itemId) => _build('/api/v1/items/$itemId/stream');

  /// Sidecar WebVTT subtitle track.
  Uri subtitle(String itemId, String trackId) =>
      _build('/api/v1/items/$itemId/subtitles/$trackId');

  /// Beacon SSE stream for cross-device resume.
  Uri beacon() => _build('/api/v1/beacon');

  /// A transcode-session HLS artifact (master/variant playlist, init, segment).
  Uri transcodeFile(String sessionId, String file) =>
      _build('/api/v1/transcode/$sessionId/$file');

  Uri _build(String path, [Map<String, String>? query]) {
    final params = <String, String>{...?query};
    final token = _token;
    if (token != null && token.isNotEmpty) {
      params['token'] = token;
    }
    return Uri.parse('$_baseUrl$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }
}
