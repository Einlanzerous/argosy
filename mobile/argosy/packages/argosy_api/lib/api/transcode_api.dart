//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class TranscodeApi {
  TranscodeApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Transcode cache usage (Ballast)
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getTranscodeCacheWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/transcode/cache';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Transcode cache usage (Ballast)
  Future<TranscodeCacheStats?> getTranscodeCache({ Future<void>? abortTrigger, }) async {
    final response = await getTranscodeCacheWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'TranscodeCacheStats',) as TranscodeCacheStats;
    
    }
    return null;
  }

  /// Encoders available on this host and the selected one
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getTranscodeCapabilitiesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/transcode/capabilities';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Encoders available on this host and the selected one
  Future<TranscodeCapabilities?> getTranscodeCapabilities({ Future<void>? abortTrigger, }) async {
    final response = await getTranscodeCapabilitiesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'TranscodeCapabilities',) as TranscodeCapabilities;
    
    }
    return null;
  }

  /// HLS artifact for a session (master/variant playlist, init, or segment)
  ///
  /// Serves a session's HLS artifacts: the master playlist (`index.m3u8`), per-variant playlists (`stream_N.m3u8`), fMP4 init segments (`init_N.mp4`), and media segments (`stream_N_NNNNN.m4s`). The filename is allow-listed server-side. `index.m3u8` returns 503 while the session is still starting (no playlist written yet). 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] sessionId (required):
  ///
  /// * [String] file (required):
  Future<Response> getTranscodeFileWithHttpInfo(String sessionId, String file, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/transcode/{sessionId}/{file}'
      .replaceAll('{sessionId}', sessionId)
      .replaceAll('{file}', file);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// HLS artifact for a session (master/variant playlist, init, or segment)
  ///
  /// Serves a session's HLS artifacts: the master playlist (`index.m3u8`), per-variant playlists (`stream_N.m3u8`), fMP4 init segments (`init_N.mp4`), and media segments (`stream_N_NNNNN.m4s`). The filename is allow-listed server-side. `index.m3u8` returns 503 while the session is still starting (no playlist written yet). 
  ///
  /// Parameters:
  ///
  /// * [String] sessionId (required):
  ///
  /// * [String] file (required):
  Future<String?> getTranscodeFile(String sessionId, String file, { Future<void>? abortTrigger, }) async {
    final response = await getTranscodeFileWithHttpInfo(sessionId, file, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'String',) as String;
    
    }
    return null;
  }

  /// Live transcode sessions for the current account (The Helm)
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listTranscodeSessionsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/transcode/sessions';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Live transcode sessions for the current account (The Helm)
  Future<List<TranscodeSession>?> listTranscodeSessions({ Future<void>? abortTrigger, }) async {
    final response = await listTranscodeSessionsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<TranscodeSession>') as List)
        .cast<TranscodeSession>()
        .toList(growable: false);

    }
    return null;
  }

  /// Start (or join) an HLS transcode session for an item
  ///
  /// Starts a server-side transcode and returns the session plus its HLS playlist URL. Repeat requests for the same item + offset join the existing session instead of spawning a second ffmpeg. Returns 503 when the server is at its transcode-session limit (back-pressure). 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [TranscodeStartRequest] transcodeStartRequest:
  Future<Response> startTranscodeWithHttpInfo(String itemId, { TranscodeStartRequest? transcodeStartRequest, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/transcode'
      .replaceAll('{itemId}', itemId);

    // ignore: prefer_final_locals
    Object? postBody = transcodeStartRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Start (or join) an HLS transcode session for an item
  ///
  /// Starts a server-side transcode and returns the session plus its HLS playlist URL. Repeat requests for the same item + offset join the existing session instead of spawning a second ffmpeg. Returns 503 when the server is at its transcode-session limit (back-pressure). 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [TranscodeStartRequest] transcodeStartRequest:
  Future<TranscodeSession?> startTranscode(String itemId, { TranscodeStartRequest? transcodeStartRequest, Future<void>? abortTrigger, }) async {
    final response = await startTranscodeWithHttpInfo(itemId, transcodeStartRequest: transcodeStartRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'TranscodeSession',) as TranscodeSession;
    
    }
    return null;
  }

  /// Stop a transcode session and purge its output
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] sessionId (required):
  Future<Response> stopTranscodeWithHttpInfo(String sessionId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/transcode/{sessionId}'
      .replaceAll('{sessionId}', sessionId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Stop a transcode session and purge its output
  ///
  /// Parameters:
  ///
  /// * [String] sessionId (required):
  Future<void> stopTranscode(String sessionId, { Future<void>? abortTrigger, }) async {
    final response = await stopTranscodeWithHttpInfo(sessionId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }
}
