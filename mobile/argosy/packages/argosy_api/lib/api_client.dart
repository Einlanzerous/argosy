//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ApiClient {
  ApiClient({this.basePath = 'http://localhost', this.authentication,});

  final String basePath;
  final Authentication? authentication;

  var _client = Client();
  final _defaultHeaderMap = <String, String>{};

  /// Returns the current HTTP [Client] instance to use in this class.
  ///
  /// The return value is guaranteed to never be null.
  Client get client => _client;

  /// Requests to use a new HTTP [Client] in this class.
  set client(Client newClient) {
    _client = newClient;
  }

  Map<String, String> get defaultHeaderMap => _defaultHeaderMap;

  void addDefaultHeader(String key, String value) {
     _defaultHeaderMap[key] = value;
  }

  // We don't use a Map<String, String> for queryParams.
  // If collectionFormat is 'multi', a key might appear multiple times.
  Future<Response> invokeAPI(
    String path,
    String method,
    List<QueryParam> queryParams,
    Object? body,
    Map<String, String> headerParams,
    Map<String, String> formParams,
    String? contentType, {
    Future<void>? abortTrigger,
  }) async {
    await authentication?.applyToParams(queryParams, headerParams);

    headerParams.addAll(_defaultHeaderMap);
    if (contentType != null) {
      headerParams['Content-Type'] = contentType;
    }

    final urlEncodedQueryParams = queryParams.map((param) => '$param');
    final queryString = urlEncodedQueryParams.isNotEmpty ? '?${urlEncodedQueryParams.join('&')}' : '';
    final uri = Uri.parse('$basePath$path$queryString');

    try {
      // Special case for uploading a single file which isn't a 'multipart/form-data'.
      if (
        body is MultipartFile && (contentType == null ||
        !contentType.toLowerCase().startsWith('multipart/form-data'))
      ) {
        final request = AbortableStreamedRequest(method, uri, abortTrigger: abortTrigger);
        request.headers.addAll(headerParams);
        request.contentLength = body.length;
        body.finalize().listen(
          request.sink.add,
          onDone: request.sink.close,
          // ignore: avoid_types_on_closure_parameters
          onError: (Object error, StackTrace trace) => request.sink.close(),
          cancelOnError: true,
        );
        final response = await _client.send(request);
        return Response.fromStream(response);
      }

      if (body is MultipartRequest) {
        final request = AbortableMultipartRequest(method, uri, abortTrigger: abortTrigger);
        request.fields.addAll(body.fields);
        request.files.addAll(body.files);
        request.headers.addAll(body.headers);
        request.headers.addAll(headerParams);
        final response = await _client.send(request);
        return Response.fromStream(response);
      }

      final msgBody = contentType == 'application/x-www-form-urlencoded'
        ? formParams
        : await serializeAsync(body);
      final nullableHeaderParams = headerParams.isEmpty ? null : headerParams;

      final request = AbortableRequest(method, uri, abortTrigger: abortTrigger);
      if (nullableHeaderParams != null) {
        request.headers.addAll(nullableHeaderParams);
      }
      if (msgBody is String && msgBody.isNotEmpty) {
        request.body = msgBody;
      } else if (msgBody is List<int> && msgBody.isNotEmpty) {
        request.bodyBytes = msgBody;
      } else if (msgBody is Map<String, String>) {
        request.bodyFields = msgBody;
      }
      final response = await _client.send(request);
      return Response.fromStream(response);
    } on SocketException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Socket operation failed: $method $path',
        error,
        trace,
      );
    } on TlsException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'TLS/SSL communication failed: $method $path',
        error,
        trace,
      );
    } on IOException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'I/O operation failed: $method $path',
        error,
        trace,
      );
    } on ClientException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'HTTP connection failed: $method $path',
        error,
        trace,
      );
    } on Exception catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Exception occurred: $method $path',
        error,
        trace,
      );
    }
  }

  Future<dynamic> deserializeAsync(String value, String targetType, {bool growable = false,}) async =>
    // ignore: deprecated_member_use_from_same_package
    deserialize(value, targetType, growable: growable);

  @Deprecated('Scheduled for removal in OpenAPI Generator 6.x. Use deserializeAsync() instead.')
  dynamic deserialize(String value, String targetType, {bool growable = false,}) {
    // Remove all spaces. Necessary for regular expressions as well.
    targetType = targetType.replaceAll(' ', ''); // ignore: parameter_assignments

    // If the expected target type is String, nothing to do...
    return targetType == 'String'
      ? value
      : fromJson(json.decode(value), targetType, growable: growable);
  }

  // ignore: deprecated_member_use_from_same_package
  Future<String> serializeAsync(Object? value) async => serialize(value);

  @Deprecated('Scheduled for removal in OpenAPI Generator 6.x. Use serializeAsync() instead.')
  String serialize(Object? value) => value == null ? '' : json.encode(value);

  /// Returns a native instance of an OpenAPI class matching the [specified type][targetType].
  static dynamic fromJson(dynamic value, String targetType, {bool growable = false,}) {
    try {
      switch (targetType) {
        case 'String':
          return value is String ? value : value.toString();
        case 'int':
          return value is int ? value : int.parse('$value');
        case 'double':
          return value is double ? value : double.parse('$value');
        case 'bool':
          if (value is bool) {
            return value;
          }
          final valueString = '$value'.toLowerCase();
          return valueString == 'true' || valueString == '1';
        case 'DateTime':
          return value is DateTime ? value : DateTime.tryParse(value);
        case 'Account':
          return Account.fromJson(value);
        case 'AddLabelRequest':
          return AddLabelRequest.fromJson(value);
        case 'AddVaultItemRequest':
          return AddVaultItemRequest.fromJson(value);
        case 'ContinueItem':
          return ContinueItem.fromJson(value);
        case 'CreateLibraryRequest':
          return CreateLibraryRequest.fromJson(value);
        case 'CreateVaultRequest':
          return CreateVaultRequest.fromJson(value);
        case 'Device':
          return Device.fromJson(value);
        case 'DevicePreferences':
          return DevicePreferences.fromJson(value);
        case 'DeviceRef':
          return DeviceRef.fromJson(value);
        case 'DeviceRegistrationRequest':
          return DeviceRegistrationRequest.fromJson(value);
        case 'DeviceRegistrationResponse':
          return DeviceRegistrationResponse.fromJson(value);
        case 'DeviceRenameRequest':
          return DeviceRenameRequest.fromJson(value);
        case 'DeviceSwitchRequest':
          return DeviceSwitchRequest.fromJson(value);
        case 'EpisodeSummary':
          return EpisodeSummary.fromJson(value);
        case 'Error':
          return Error.fromJson(value);
        case 'Facet':
          return Facet.fromJson(value);
        case 'LinkApproveRequest':
          return LinkApproveRequest.fromJson(value);
        case 'LinkStartResponse':
          return LinkStartResponse.fromJson(value);
        case 'LinkStatusResponse':
          return LinkStatusResponse.fromJson(value);
        case 'LoginRequest':
          return LoginRequest.fromJson(value);
        case 'LoginResponse':
          return LoginResponse.fromJson(value);
        case 'MediaItemDetail':
          return MediaItemDetail.fromJson(value);
        case 'MediaItemPage':
          return MediaItemPage.fromJson(value);
        case 'MediaItemSummary':
          return MediaItemSummary.fromJson(value);
        case 'ModelLibrary':
          return ModelLibrary.fromJson(value);
        case 'OnDeckItem':
          return OnDeckItem.fromJson(value);
        case 'PingResponse':
          return PingResponse.fromJson(value);
        case 'PlayState':
          return PlayState.fromJson(value);
        case 'PlaybackInfo':
          return PlaybackInfo.fromJson(value);
        case 'PlaybackSession':
          return PlaybackSession.fromJson(value);
        case 'ProfileCreateRequest':
          return ProfileCreateRequest.fromJson(value);
        case 'ProfileSummary':
          return ProfileSummary.fromJson(value);
        case 'ProfileUpdateRequest':
          return ProfileUpdateRequest.fromJson(value);
        case 'ProgressUpdate':
          return ProgressUpdate.fromJson(value);
        case 'ReorderVaultRequest':
          return ReorderVaultRequest.fromJson(value);
        case 'Role':
          return RoleTypeTransformer().decode(value);
        case 'ScanLibraryResult':
          return ScanLibraryResult.fromJson(value);
        case 'ScanStatus':
          return ScanStatus.fromJson(value);
        case 'SearchResults':
          return SearchResults.fromJson(value);
        case 'SeasonSummary':
          return SeasonSummary.fromJson(value);
        case 'SeriesDetail':
          return SeriesDetail.fromJson(value);
        case 'SeriesPage':
          return SeriesPage.fromJson(value);
        case 'SeriesSummary':
          return SeriesSummary.fromJson(value);
        case 'Session':
          return Session.fromJson(value);
        case 'SubtitleTrack':
          return SubtitleTrack.fromJson(value);
        case 'TranscodeCacheStats':
          return TranscodeCacheStats.fromJson(value);
        case 'TranscodeCapabilities':
          return TranscodeCapabilities.fromJson(value);
        case 'TranscodeProgress':
          return TranscodeProgress.fromJson(value);
        case 'TranscodeSession':
          return TranscodeSession.fromJson(value);
        case 'TranscodeStartRequest':
          return TranscodeStartRequest.fromJson(value);
        case 'UpdateVaultRequest':
          return UpdateVaultRequest.fromJson(value);
        case 'UserPreferences':
          return UserPreferences.fromJson(value);
        case 'UserProfile':
          return UserProfile.fromJson(value);
        case 'Vault':
          return Vault.fromJson(value);
        case 'VaultDetail':
          return VaultDetail.fromJson(value);
        case 'VaultEntry':
          return VaultEntry.fromJson(value);
        case 'WatchedUpdate':
          return WatchedUpdate.fromJson(value);
        default:
          dynamic match;
          if (value is List && (match = _regList.firstMatch(targetType)?.group(1)) != null) {
            return value
              .map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,))
              .toList(growable: growable);
          }
          if (value is Set && (match = _regSet.firstMatch(targetType)?.group(1)) != null) {
            return value
              .map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,))
              .toSet();
          }
          if (value is Map && (match = _regMap.firstMatch(targetType)?.group(1)) != null) {
            return Map<String, dynamic>.fromIterables(
              value.keys.cast<String>(),
              value.values.map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,)),
            );
          }
      }
    } on Exception catch (error, trace) {
      throw ApiException.withInner(HttpStatus.internalServerError, 'Exception during deserialization.', error, trace,);
    }
    throw ApiException(HttpStatus.internalServerError, 'Could not find a suitable class for deserialization',);
  }
}

/// Primarily intended for use in an isolate.
class DeserializationMessage {
  const DeserializationMessage({
    required this.json,
    required this.targetType,
    this.growable = false,
  });

  /// The JSON value to deserialize.
  final String json;

  /// Target type to deserialize to.
  final String targetType;

  /// Whether to make deserialized lists or maps growable.
  final bool growable;
}

/// Primarily intended for use in an isolate.
Future<dynamic> decodeAsync(DeserializationMessage message) async {
  // Remove all spaces. Necessary for regular expressions as well.
  final targetType = message.targetType.replaceAll(' ', '');

  // If the expected target type is String, nothing to do...
  return targetType == 'String'
    ? message.json
    : json.decode(message.json);
}

/// Primarily intended for use in an isolate.
Future<dynamic> deserializeAsync(DeserializationMessage message) async {
  // Remove all spaces. Necessary for regular expressions as well.
  final targetType = message.targetType.replaceAll(' ', '');

  // If the expected target type is String, nothing to do...
  return targetType == 'String'
    ? message.json
    : ApiClient.fromJson(
        json.decode(message.json),
        targetType,
        growable: message.growable,
      );
}

/// Primarily intended for use in an isolate.
Future<String> serializeAsync(Object? value) async => value == null ? '' : json.encode(value);
