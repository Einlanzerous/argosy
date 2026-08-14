//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class StowApi {
  StowApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Cancel a packaging job, or release a collected one
  ///
  /// Serves both ends of the job's life: it cancels an encode still in flight, and it releases the server-side copy once the device has the bytes. Either way the artifact is purged. Deleting the job does not touch what the device already downloaded. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  Future<Response> deleteStowJobWithHttpInfo(String jobId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/stow/{jobId}'
      .replaceAll('{jobId}', jobId);

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

  /// Cancel a packaging job, or release a collected one
  ///
  /// Serves both ends of the job's life: it cancels an encode still in flight, and it releases the server-side copy once the device has the bytes. Either way the artifact is purged. Deleting the job does not touch what the device already downloaded. 
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  Future<void> deleteStowJob(String jobId, { Future<void>? abortTrigger, }) async {
    final response = await deleteStowJobWithHttpInfo(jobId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Download a ready package
  ///
  /// Serves the packaged MP4 with byte-range support, so an interrupted download resumes instead of restarting — the difference between a 2 GB download surviving a walk out of Wi-Fi range and not. Auth is the per-device token via the bearer header OR a `token` query param, matching the stream endpoint. Returns 409 while the job is still packaging. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<Response> getStowFileWithHttpInfo(String jobId, { String? token, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/stow/{jobId}/file'
      .replaceAll('{jobId}', jobId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (token != null) {
      queryParams.addAll(_queryParams('', 'token', token));
    }

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

  /// Download a ready package
  ///
  /// Serves the packaged MP4 with byte-range support, so an interrupted download resumes instead of restarting — the difference between a 2 GB download surviving a walk out of Wi-Fi range and not. Auth is the per-device token via the bearer header OR a `token` query param, matching the stream endpoint. Returns 409 while the job is still packaging. 
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<MultipartFile?> getStowFile(String jobId, { String? token, Future<void>? abortTrigger, }) async {
    final response = await getStowFileWithHttpInfo(jobId, token: token, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'MultipartFile',) as MultipartFile;
    
    }
    return null;
  }

  /// Poll a packaging job
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  Future<Response> getStowJobWithHttpInfo(String jobId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/stow/{jobId}'
      .replaceAll('{jobId}', jobId);

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

  /// Poll a packaging job
  ///
  /// Parameters:
  ///
  /// * [String] jobId (required):
  Future<StowJob?> getStowJob(String jobId, { Future<void>? abortTrigger, }) async {
    final response = await getStowJobWithHttpInfo(jobId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'StowJob',) as StowJob;
    
    }
    return null;
  }

  /// Packaging jobs for the current account
  ///
  /// Only covers items that needed packaging. A passthrough stow leaves no server-side state, so it never appears here — the device's own list of what it has stowed is the source of truth for that. 
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listStowJobsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/stow';

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

  /// Packaging jobs for the current account
  ///
  /// Only covers items that needed packaging. A passthrough stow leaves no server-side state, so it never appears here — the device's own list of what it has stowed is the source of truth for that. 
  Future<List<StowJob>?> listStowJobs({ Future<void>? abortTrigger, }) async {
    final response = await listStowJobsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<StowJob>') as List)
        .cast<StowJob>()
        .toList(growable: false);

    }
    return null;
  }

  /// Pack an item away for offline viewing
  ///
  /// Asks the server to make the item downloadable for offline playback (ARGY-49), and returns how that will happen.  The decision is per item. A source the client can already play, at a size worth keeping on a device, is handed over untouched — the response comes back `method: passthrough`, `state: ready`, and a `downloadUrl` pointing at the existing range-capable stream endpoint. No encode runs and no server-side job exists.  Otherwise the server queues a packaging job that re-encodes the source into a single progressive MP4 (H.264 8-bit + AAC, capped at 1080p) — `method: package` with an `id` to poll. Repeat requests for the same item join the job already running rather than starting a second encode; a job that previously failed is reset and retried.  Either way the client ends up downloading exactly one file, which is what makes offline playback a plain local-file path rather than an offline HLS problem. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [StowRequest] stowRequest:
  Future<Response> stowItemWithHttpInfo(String itemId, { StowRequest? stowRequest, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/stow'
      .replaceAll('{itemId}', itemId);

    // ignore: prefer_final_locals
    Object? postBody = stowRequest;

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

  /// Pack an item away for offline viewing
  ///
  /// Asks the server to make the item downloadable for offline playback (ARGY-49), and returns how that will happen.  The decision is per item. A source the client can already play, at a size worth keeping on a device, is handed over untouched — the response comes back `method: passthrough`, `state: ready`, and a `downloadUrl` pointing at the existing range-capable stream endpoint. No encode runs and no server-side job exists.  Otherwise the server queues a packaging job that re-encodes the source into a single progressive MP4 (H.264 8-bit + AAC, capped at 1080p) — `method: package` with an `id` to poll. Repeat requests for the same item join the job already running rather than starting a second encode; a job that previously failed is reset and retried.  Either way the client ends up downloading exactly one file, which is what makes offline playback a plain local-file path rather than an offline HLS problem. 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [StowRequest] stowRequest:
  Future<StowJob?> stowItem(String itemId, { StowRequest? stowRequest, Future<void>? abortTrigger, }) async {
    final response = await stowItemWithHttpInfo(itemId, stowRequest: stowRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'StowJob',) as StowJob;
    
    }
    return null;
  }
}
