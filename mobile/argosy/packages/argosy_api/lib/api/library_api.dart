//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class LibraryApi {
  LibraryApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Add a film or series to a vault
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [AddVaultItemRequest] addVaultItemRequest (required):
  Future<Response> addVaultItemWithHttpInfo(String vaultId, AddVaultItemRequest addVaultItemRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}/items'
      .replaceAll('{vaultId}', vaultId);

    // ignore: prefer_final_locals
    Object? postBody = addVaultItemRequest;

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

  /// Add a film or series to a vault
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [AddVaultItemRequest] addVaultItemRequest (required):
  Future<VaultEntry?> addVaultItem(String vaultId, AddVaultItemRequest addVaultItemRequest, { Future<void>? abortTrigger, }) async {
    final response = await addVaultItemWithHttpInfo(vaultId, addVaultItemRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'VaultEntry',) as VaultEntry;
    
    }
    return null;
  }

  /// SSE stream of the current user's live play-state events (Beacon)
  ///
  /// Server-Sent Events stream of play_state changes for the authenticated user, powering cross-device resume/handoff. Authenticates via ?token= (an EventSource cannot set the Authorization header). Each message is `event: position` with a JSON data payload (see PlaybackSession-like fields). The client (EventSource) auto-reconnects; on reconnect it reconciles missed updates via a /continue or /progress fetch. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] token:
  ///   Per-device bearer token (EventSource can't set headers).
  Future<Response> beaconStreamWithHttpInfo({ String? token, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/beacon';

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

  /// SSE stream of the current user's live play-state events (Beacon)
  ///
  /// Server-Sent Events stream of play_state changes for the authenticated user, powering cross-device resume/handoff. Authenticates via ?token= (an EventSource cannot set the Authorization header). Each message is `event: position` with a JSON data payload (see PlaybackSession-like fields). The client (EventSource) auto-reconnects; on reconnect it reconciles missed updates via a /continue or /progress fetch. 
  ///
  /// Parameters:
  ///
  /// * [String] token:
  ///   Per-device bearer token (EventSource can't set headers).
  Future<String?> beaconStream({ String? token, Future<void>? abortTrigger, }) async {
    final response = await beaconStreamWithHttpInfo(token: token, abortTrigger: abortTrigger,);
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

  /// Register a new media library (admin only)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [CreateLibraryRequest] createLibraryRequest (required):
  Future<Response> createLibraryWithHttpInfo(CreateLibraryRequest createLibraryRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/libraries';

    // ignore: prefer_final_locals
    Object? postBody = createLibraryRequest;

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

  /// Register a new media library (admin only)
  ///
  /// Parameters:
  ///
  /// * [CreateLibraryRequest] createLibraryRequest (required):
  Future<ModelLibrary?> createLibrary(CreateLibraryRequest createLibraryRequest, { Future<void>? abortTrigger, }) async {
    final response = await createLibraryWithHttpInfo(createLibraryRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ModelLibrary',) as ModelLibrary;
    
    }
    return null;
  }

  /// Create a vault
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [CreateVaultRequest] createVaultRequest (required):
  Future<Response> createVaultWithHttpInfo(CreateVaultRequest createVaultRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults';

    // ignore: prefer_final_locals
    Object? postBody = createVaultRequest;

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

  /// Create a vault
  ///
  /// Parameters:
  ///
  /// * [CreateVaultRequest] createVaultRequest (required):
  Future<Vault?> createVault(CreateVaultRequest createVaultRequest, { Future<void>? abortTrigger, }) async {
    final response = await createVaultWithHttpInfo(createVaultRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Vault',) as Vault;
    
    }
    return null;
  }

  /// Remove a library and its items (admin only)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  Future<Response> deleteLibraryWithHttpInfo(String libraryId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/libraries/{libraryId}'
      .replaceAll('{libraryId}', libraryId);

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

  /// Remove a library and its items (admin only)
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  Future<void> deleteLibrary(String libraryId, { Future<void>? abortTrigger, }) async {
    final response = await deleteLibraryWithHttpInfo(libraryId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Delete a vault (owner or admin)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  Future<Response> deleteVaultWithHttpInfo(String vaultId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}'
      .replaceAll('{vaultId}', vaultId);

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

  /// Delete a vault (owner or admin)
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  Future<void> deleteVault(String vaultId, { Future<void>? abortTrigger, }) async {
    final response = await deleteVaultWithHttpInfo(vaultId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Media item detail with effective metadata
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<Response> getMediaItemWithHttpInfo(String itemId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}'
      .replaceAll('{itemId}', itemId);

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

  /// Media item detail with effective metadata
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<MediaItemDetail?> getMediaItem(String itemId, { Future<void>? abortTrigger, }) async {
    final response = await getMediaItemWithHttpInfo(itemId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'MediaItemDetail',) as MediaItemDetail;
    
    }
    return null;
  }

  /// The next episode after this one in its series
  ///
  /// Given a series episode, returns the next playable episode in season/ episode order — rolling across season boundaries to the next season's first episode. Returns 404 when the item is the last episode of the series, has no following playable episode, or isn't a series episode at all (e.g. a film). Powers the player's auto-advance \"Up Next\" overlay. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<Response> getNextEpisodeWithHttpInfo(String itemId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/next-episode'
      .replaceAll('{itemId}', itemId);

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

  /// The next episode after this one in its series
  ///
  /// Given a series episode, returns the next playable episode in season/ episode order — rolling across season boundaries to the next season's first episode. Returns 404 when the item is the last episode of the series, has no following playable episode, or isn't a series episode at all (e.g. a film). Powers the player's auto-advance \"Up Next\" overlay. 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<OnDeckItem?> getNextEpisode(String itemId, { Future<void>? abortTrigger, }) async {
    final response = await getNextEpisodeWithHttpInfo(itemId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'OnDeckItem',) as OnDeckItem;
    
    }
    return null;
  }

  /// Direct-play capability decision for the item
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<Response> getPlaybackInfoWithHttpInfo(String itemId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/playback'
      .replaceAll('{itemId}', itemId);

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

  /// Direct-play capability decision for the item
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<PlaybackInfo?> getPlaybackInfo(String itemId, { Future<void>? abortTrigger, }) async {
    final response = await getPlaybackInfoWithHttpInfo(itemId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PlaybackInfo',) as PlaybackInfo;
    
    }
    return null;
  }

  /// Current play-state (resume position) for the item
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<Response> getProgressWithHttpInfo(String itemId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/progress'
      .replaceAll('{itemId}', itemId);

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

  /// Current play-state (resume position) for the item
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<PlayState?> getProgress(String itemId, { Future<void>? abortTrigger, }) async {
    final response = await getProgressWithHttpInfo(itemId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PlayState',) as PlayState;
    
    }
    return null;
  }

  /// Current/last scan sweep status
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getScanStatusWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/scan/status';

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

  /// Current/last scan sweep status
  Future<ScanStatus?> getScanStatus({ Future<void>? abortTrigger, }) async {
    final response = await getScanStatusWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ScanStatus',) as ScanStatus;
    
    }
    return null;
  }

  /// Series detail with seasons and episodes
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] seriesId (required):
  Future<Response> getSeriesWithHttpInfo(String seriesId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/series/{seriesId}'
      .replaceAll('{seriesId}', seriesId);

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

  /// Series detail with seasons and episodes
  ///
  /// Parameters:
  ///
  /// * [String] seriesId (required):
  Future<SeriesDetail?> getSeries(String seriesId, { Future<void>? abortTrigger, }) async {
    final response = await getSeriesWithHttpInfo(seriesId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SeriesDetail',) as SeriesDetail;
    
    }
    return null;
  }

  /// A subtitle track as WebVTT
  ///
  /// Produces (and disk-caches) the track as WebVTT. Auth is the per-device token via the bearer header OR a `token` query param, since an HTML5 `<track>` element cannot set Authorization. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [String] trackId (required):
  ///   Track id from the list endpoint (e.g. `embedded:3`, `os:12345`).
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<Response> getSubtitleWithHttpInfo(String itemId, String trackId, { String? token, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/subtitles/{trackId}'
      .replaceAll('{itemId}', itemId)
      .replaceAll('{trackId}', trackId);

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

  /// A subtitle track as WebVTT
  ///
  /// Produces (and disk-caches) the track as WebVTT. Auth is the per-device token via the bearer header OR a `token` query param, since an HTML5 `<track>` element cannot set Authorization. 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [String] trackId (required):
  ///   Track id from the list endpoint (e.g. `embedded:3`, `os:12345`).
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<String?> getSubtitle(String itemId, String trackId, { String? token, Future<void>? abortTrigger, }) async {
    final response = await getSubtitleWithHttpInfo(itemId, trackId, token: token, abortTrigger: abortTrigger,);
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

  /// Vault detail with its items
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  Future<Response> getVaultWithHttpInfo(String vaultId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}'
      .replaceAll('{vaultId}', vaultId);

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

  /// Vault detail with its items
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  Future<VaultDetail?> getVault(String vaultId, { Future<void>? abortTrigger, }) async {
    final response = await getVaultWithHttpInfo(vaultId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'VaultDetail',) as VaultDetail;
    
    }
    return null;
  }

  /// Continue-watching / on-deck items for the current profile
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listContinueWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/continue';

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

  /// Continue-watching / on-deck items for the current profile
  Future<List<ContinueItem>?> listContinue({ Future<void>? abortTrigger, }) async {
    final response = await listContinueWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<ContinueItem>') as List)
        .cast<ContinueItem>()
        .toList(growable: false);

    }
    return null;
  }

  /// Most common genres across the account's manifest
  ///
  /// The most-used genres across the account's films and series, ranked by item count — used to surface discovery chips.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  ///   Max facets to return.
  Future<Response> listFacetsWithHttpInfo({ int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/facets';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
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

  /// Most common genres across the account's manifest
  ///
  /// The most-used genres across the account's films and series, ranked by item count — used to surface discovery chips.
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  ///   Max facets to return.
  Future<List<Facet>?> listFacets({ int? limit, Future<void>? abortTrigger, }) async {
    final response = await listFacetsWithHttpInfo(limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<Facet>') as List)
        .cast<Facet>()
        .toList(growable: false);

    }
    return null;
  }

  /// List the account's libraries
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listLibrariesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/libraries';

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

  /// List the account's libraries
  Future<List<ModelLibrary>?> listLibraries({ Future<void>? abortTrigger, }) async {
    final response = await listLibrariesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<ModelLibrary>') as List)
        .cast<ModelLibrary>()
        .toList(growable: false);

    }
    return null;
  }

  /// Browse movies in a library
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  ///
  /// * [String] sort:
  ///
  /// * [List<String>] genre:
  ///   Filter to items in any of these genres (repeatable).
  ///
  /// * [num] ratingMin:
  ///   Minimum effective rating (0–10).
  ///
  /// * [String] watched:
  ///   Per-user watched state.
  ///
  /// * [int] yearFrom:
  ///   Earliest release year (inclusive).
  ///
  /// * [int] yearTo:
  ///   Latest release year (inclusive).
  Future<Response> listMoviesWithHttpInfo(String libraryId, { int? limit, int? offset, String? sort, List<String>? genre, num? ratingMin, String? watched, int? yearFrom, int? yearTo, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/libraries/{libraryId}/movies'
      .replaceAll('{libraryId}', libraryId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }
    if (offset != null) {
      queryParams.addAll(_queryParams('', 'offset', offset));
    }
    if (sort != null) {
      queryParams.addAll(_queryParams('', 'sort', sort));
    }
    if (genre != null) {
      queryParams.addAll(_queryParams('multi', 'genre', genre));
    }
    if (ratingMin != null) {
      queryParams.addAll(_queryParams('', 'rating_min', ratingMin));
    }
    if (watched != null) {
      queryParams.addAll(_queryParams('', 'watched', watched));
    }
    if (yearFrom != null) {
      queryParams.addAll(_queryParams('', 'year_from', yearFrom));
    }
    if (yearTo != null) {
      queryParams.addAll(_queryParams('', 'year_to', yearTo));
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

  /// Browse movies in a library
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  ///
  /// * [String] sort:
  ///
  /// * [List<String>] genre:
  ///   Filter to items in any of these genres (repeatable).
  ///
  /// * [num] ratingMin:
  ///   Minimum effective rating (0–10).
  ///
  /// * [String] watched:
  ///   Per-user watched state.
  ///
  /// * [int] yearFrom:
  ///   Earliest release year (inclusive).
  ///
  /// * [int] yearTo:
  ///   Latest release year (inclusive).
  Future<MediaItemPage?> listMovies(String libraryId, { int? limit, int? offset, String? sort, List<String>? genre, num? ratingMin, String? watched, int? yearFrom, int? yearTo, Future<void>? abortTrigger, }) async {
    final response = await listMoviesWithHttpInfo(libraryId, limit: limit, offset: offset, sort: sort, genre: genre, ratingMin: ratingMin, watched: watched, yearFrom: yearFrom, yearTo: yearTo, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'MediaItemPage',) as MediaItemPage;
    
    }
    return null;
  }

  /// On-deck (up-next) episodes for series the user is currently watching
  ///
  /// The next unstarted episode of each series the current profile has made progress in — i.e. has watched at least one episode and has a later episode not yet started. Excludes in-progress items (those live in /continue), so the two rows don't overlap. Newest activity first. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<Response> listOnDeckWithHttpInfo({ int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ondeck';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
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

  /// On-deck (up-next) episodes for series the user is currently watching
  ///
  /// The next unstarted episode of each series the current profile has made progress in — i.e. has watched at least one episode and has a later episode not yet started. Excludes in-progress items (those live in /continue), so the two rows don't overlap. Newest activity first. 
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<List<OnDeckItem>?> listOnDeck({ int? limit, Future<void>? abortTrigger, }) async {
    final response = await listOnDeckWithHttpInfo(limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<OnDeckItem>') as List)
        .cast<OnDeckItem>()
        .toList(growable: false);

    }
    return null;
  }

  /// Live playback sessions (who's watching what, where, now)
  ///
  /// Active playback sessions, most-recently-active first. Admins see the whole account; a viewer sees only their own. A session that owns a transcode session is annotated with its encoder + method (reconciled with The Helm). 
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listPlaybackSessionsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/sessions';

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

  /// Live playback sessions (who's watching what, where, now)
  ///
  /// Active playback sessions, most-recently-active first. Admins see the whole account; a viewer sees only their own. A session that owns a transcode session is annotated with its encoder + method (reconciled with The Helm). 
  Future<List<PlaybackSession>?> listPlaybackSessions({ Future<void>? abortTrigger, }) async {
    final response = await listPlaybackSessionsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<PlaybackSession>') as List)
        .cast<PlaybackSession>()
        .toList(growable: false);

    }
    return null;
  }

  /// Recently-added items (films + series) across the account
  ///
  /// A unified \"newly arrived\" feed across every library: standalone films and series, newest first. A series' arrival time is the most recent of its episodes' added-at timestamps, so adding an episode resurfaces the series (deduped to a single card) rather than listing each episode. Each item's `kind` is \"movie\" or \"series\". 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<Response> listRecentWithHttpInfo({ int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/recent';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
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

  /// Recently-added items (films + series) across the account
  ///
  /// A unified \"newly arrived\" feed across every library: standalone films and series, newest first. A series' arrival time is the most recent of its episodes' added-at timestamps, so adding an episode resurfaces the series (deduped to a single card) rather than listing each episode. Each item's `kind` is \"movie\" or \"series\". 
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<List<MediaItemSummary>?> listRecent({ int? limit, Future<void>? abortTrigger, }) async {
    final response = await listRecentWithHttpInfo(limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<MediaItemSummary>') as List)
        .cast<MediaItemSummary>()
        .toList(growable: false);

    }
    return null;
  }

  /// Browse series in a library
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  ///
  /// * [String] sort:
  ///
  /// * [List<String>] genre:
  ///   Filter to series in any of these genres (repeatable).
  ///
  /// * [num] ratingMin:
  ///   Minimum effective rating (0–10).
  ///
  /// * [String] watched:
  ///   Per-user watched state (aggregated over episodes).
  ///
  /// * [int] yearFrom:
  ///   Earliest release year (inclusive).
  ///
  /// * [int] yearTo:
  ///   Latest release year (inclusive).
  Future<Response> listSeriesWithHttpInfo(String libraryId, { int? limit, int? offset, String? sort, List<String>? genre, num? ratingMin, String? watched, int? yearFrom, int? yearTo, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/libraries/{libraryId}/series'
      .replaceAll('{libraryId}', libraryId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }
    if (offset != null) {
      queryParams.addAll(_queryParams('', 'offset', offset));
    }
    if (sort != null) {
      queryParams.addAll(_queryParams('', 'sort', sort));
    }
    if (genre != null) {
      queryParams.addAll(_queryParams('multi', 'genre', genre));
    }
    if (ratingMin != null) {
      queryParams.addAll(_queryParams('', 'rating_min', ratingMin));
    }
    if (watched != null) {
      queryParams.addAll(_queryParams('', 'watched', watched));
    }
    if (yearFrom != null) {
      queryParams.addAll(_queryParams('', 'year_from', yearFrom));
    }
    if (yearTo != null) {
      queryParams.addAll(_queryParams('', 'year_to', yearTo));
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

  /// Browse series in a library
  ///
  /// Parameters:
  ///
  /// * [String] libraryId (required):
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  ///
  /// * [String] sort:
  ///
  /// * [List<String>] genre:
  ///   Filter to series in any of these genres (repeatable).
  ///
  /// * [num] ratingMin:
  ///   Minimum effective rating (0–10).
  ///
  /// * [String] watched:
  ///   Per-user watched state (aggregated over episodes).
  ///
  /// * [int] yearFrom:
  ///   Earliest release year (inclusive).
  ///
  /// * [int] yearTo:
  ///   Latest release year (inclusive).
  Future<SeriesPage?> listSeries(String libraryId, { int? limit, int? offset, String? sort, List<String>? genre, num? ratingMin, String? watched, int? yearFrom, int? yearTo, Future<void>? abortTrigger, }) async {
    final response = await listSeriesWithHttpInfo(libraryId, limit: limit, offset: offset, sort: sort, genre: genre, ratingMin: ratingMin, watched: watched, yearFrom: yearFrom, yearTo: yearTo, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SeriesPage',) as SeriesPage;
    
    }
    return null;
  }

  /// Available subtitle tracks for an item
  ///
  /// Lists subtitle tracks resolved through the priority chain: embedded text tracks (from the container) plus OpenSubtitles candidates when configured. Each track's `id` is fetched as WebVTT from the sibling endpoint. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<Response> listSubtitlesWithHttpInfo(String itemId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/subtitles'
      .replaceAll('{itemId}', itemId);

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

  /// Available subtitle tracks for an item
  ///
  /// Lists subtitle tracks resolved through the priority chain: embedded text tracks (from the container) plus OpenSubtitles candidates when configured. Each track's `id` is fetched as WebVTT from the sibling endpoint. 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  Future<List<SubtitleTrack>?> listSubtitles(String itemId, { Future<void>? abortTrigger, }) async {
    final response = await listSubtitlesWithHttpInfo(itemId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<SubtitleTrack>') as List)
        .cast<SubtitleTrack>()
        .toList(growable: false);

    }
    return null;
  }

  /// List vaults visible to the current profile (own + shared)
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listVaultsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults';

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

  /// List vaults visible to the current profile (own + shared)
  Future<List<Vault>?> listVaults({ Future<void>? abortTrigger, }) async {
    final response = await listVaultsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<Vault>') as List)
        .cast<Vault>()
        .toList(growable: false);

    }
    return null;
  }

  /// Remove an item from a vault
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [String] entryId (required):
  Future<Response> removeVaultItemWithHttpInfo(String vaultId, String entryId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}/items/{entryId}'
      .replaceAll('{vaultId}', vaultId)
      .replaceAll('{entryId}', entryId);

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

  /// Remove an item from a vault
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [String] entryId (required):
  Future<void> removeVaultItem(String vaultId, String entryId, { Future<void>? abortTrigger, }) async {
    final response = await removeVaultItemWithHttpInfo(vaultId, entryId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Reorder a vault's items
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [ReorderVaultRequest] reorderVaultRequest (required):
  Future<Response> reorderVaultWithHttpInfo(String vaultId, ReorderVaultRequest reorderVaultRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}/order'
      .replaceAll('{vaultId}', vaultId);

    // ignore: prefer_final_locals
    Object? postBody = reorderVaultRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Reorder a vault's items
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [ReorderVaultRequest] reorderVaultRequest (required):
  Future<void> reorderVault(String vaultId, ReorderVaultRequest reorderVaultRequest, { Future<void>? abortTrigger, }) async {
    final response = await reorderVaultWithHttpInfo(vaultId, reorderVaultRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Heartbeat — upsert the resume position for the current profile
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [ProgressUpdate] progressUpdate (required):
  Future<Response> reportProgressWithHttpInfo(String itemId, ProgressUpdate progressUpdate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/progress'
      .replaceAll('{itemId}', itemId);

    // ignore: prefer_final_locals
    Object? postBody = progressUpdate;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Heartbeat — upsert the resume position for the current profile
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [ProgressUpdate] progressUpdate (required):
  Future<PlayState?> reportProgress(String itemId, ProgressUpdate progressUpdate, { Future<void>? abortTrigger, }) async {
    final response = await reportProgressWithHttpInfo(itemId, progressUpdate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PlayState',) as PlayState;
    
    }
    return null;
  }

  /// Full-text search across the account's films and series
  ///
  /// Ranked full-text search over titles, genres, cast/crew, and overviews, scoped to the calling account's libraries. Results are grouped by kind (films vs. series). The query supports typeahead — the last token of each word is treated as a prefix.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] q (required):
  ///   Search text (prefix-matched per token).
  ///
  /// * [int] limit:
  ///   Max results per group.
  Future<Response> searchWithHttpInfo(String q, { int? limit, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/search';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

      queryParams.addAll(_queryParams('', 'q', q));
    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
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

  /// Full-text search across the account's films and series
  ///
  /// Ranked full-text search over titles, genres, cast/crew, and overviews, scoped to the calling account's libraries. Results are grouped by kind (films vs. series). The query supports typeahead — the last token of each word is treated as a prefix.
  ///
  /// Parameters:
  ///
  /// * [String] q (required):
  ///   Search text (prefix-matched per token).
  ///
  /// * [int] limit:
  ///   Max results per group.
  Future<SearchResults?> search(String q, { int? limit, Future<void>? abortTrigger, }) async {
    final response = await searchWithHttpInfo(q, limit: limit, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SearchResults',) as SearchResults;
    
    }
    return null;
  }

  /// Mark every episode of a season watched / unwatched for the current profile
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] seasonId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<Response> setSeasonWatchedWithHttpInfo(String seasonId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/seasons/{seasonId}/watched'
      .replaceAll('{seasonId}', seasonId);

    // ignore: prefer_final_locals
    Object? postBody = watchedUpdate;

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

  /// Mark every episode of a season watched / unwatched for the current profile
  ///
  /// Parameters:
  ///
  /// * [String] seasonId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<WatchedBulkResult?> setSeasonWatched(String seasonId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    final response = await setSeasonWatchedWithHttpInfo(seasonId, watchedUpdate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'WatchedBulkResult',) as WatchedBulkResult;
    
    }
    return null;
  }

  /// Mark every episode of a series watched / unwatched for the current profile
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] seriesId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<Response> setSeriesWatchedWithHttpInfo(String seriesId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/series/{seriesId}/watched'
      .replaceAll('{seriesId}', seriesId);

    // ignore: prefer_final_locals
    Object? postBody = watchedUpdate;

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

  /// Mark every episode of a series watched / unwatched for the current profile
  ///
  /// Parameters:
  ///
  /// * [String] seriesId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<WatchedBulkResult?> setSeriesWatched(String seriesId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    final response = await setSeriesWatchedWithHttpInfo(seriesId, watchedUpdate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'WatchedBulkResult',) as WatchedBulkResult;
    
    }
    return null;
  }

  /// Mark an item watched / unwatched for the current profile
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<Response> setWatchedWithHttpInfo(String itemId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/watched'
      .replaceAll('{itemId}', itemId);

    // ignore: prefer_final_locals
    Object? postBody = watchedUpdate;

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

  /// Mark an item watched / unwatched for the current profile
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [WatchedUpdate] watchedUpdate (required):
  Future<PlayState?> setWatched(String itemId, WatchedUpdate watchedUpdate, { Future<void>? abortTrigger, }) async {
    final response = await setWatchedWithHttpInfo(itemId, watchedUpdate, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PlayState',) as PlayState;
    
    }
    return null;
  }

  /// Direct-play media stream with HTTP range support
  ///
  /// Streams the item's media file with byte-range support (seeking). Auth is the per-device token via the bearer header OR a `token` query param, since an HTML5 `<video>` element cannot set Authorization. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<Response> streamItemWithHttpInfo(String itemId, { String? token, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/items/{itemId}/stream'
      .replaceAll('{itemId}', itemId);

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

  /// Direct-play media stream with HTTP range support
  ///
  /// Streams the item's media file with byte-range support (seeking). Auth is the per-device token via the bearer header OR a `token` query param, since an HTML5 `<video>` element cannot set Authorization. 
  ///
  /// Parameters:
  ///
  /// * [String] itemId (required):
  ///
  /// * [String] token:
  ///   Per-device token (alternative to the bearer header).
  Future<MultipartFile?> streamItem(String itemId, { String? token, Future<void>? abortTrigger, }) async {
    final response = await streamItemWithHttpInfo(itemId, token: token, abortTrigger: abortTrigger,);
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

  /// Trigger an immediate library re-scan (\"rebuild the Manifest\")
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> triggerScanWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/scan';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


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

  /// Trigger an immediate library re-scan (\"rebuild the Manifest\")
  Future<void> triggerScan({ Future<void>? abortTrigger, }) async {
    final response = await triggerScanWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Rename / re-describe / toggle sharing (owner or admin)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [UpdateVaultRequest] updateVaultRequest (required):
  Future<Response> updateVaultWithHttpInfo(String vaultId, UpdateVaultRequest updateVaultRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/vaults/{vaultId}'
      .replaceAll('{vaultId}', vaultId);

    // ignore: prefer_final_locals
    Object? postBody = updateVaultRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PATCH',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Rename / re-describe / toggle sharing (owner or admin)
  ///
  /// Parameters:
  ///
  /// * [String] vaultId (required):
  ///
  /// * [UpdateVaultRequest] updateVaultRequest (required):
  Future<Vault?> updateVault(String vaultId, UpdateVaultRequest updateVaultRequest, { Future<void>? abortTrigger, }) async {
    final response = await updateVaultWithHttpInfo(vaultId, updateVaultRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Vault',) as Vault;
    
    }
    return null;
  }
}
