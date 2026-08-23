//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class SystemApi {
  SystemApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Readiness probe and build identity
  ///
  /// Returns 200 when the database is reachable and 503 when it is not. The body shape is IDENTICAL on both paths: a degraded service is still running a version, and it is the one most worth identifying, so `version` and `sha` must be readable from the 503 branch too. `version` is bare semver or the literal `dev`; `sha` is null when the build supplied none. Neither is ever inferred.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getHealthWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/healthz';

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

  /// Readiness probe and build identity
  ///
  /// Returns 200 when the database is reachable and 503 when it is not. The body shape is IDENTICAL on both paths: a degraded service is still running a version, and it is the one most worth identifying, so `version` and `sha` must be readable from the 503 branch too. `version` is bare semver or the literal `dev`; `sha` is null when the build supplied none. Neither is ever inferred.
  Future<HealthResponse?> getHealth({ Future<void>? abortTrigger, }) async {
    final response = await getHealthWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'HealthResponse',) as HealthResponse;
    
    }
    return null;
  }

  /// Service identity and version
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> pingWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ping';

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

  /// Service identity and version
  Future<PingResponse?> ping({ Future<void>? abortTrigger, }) async {
    final response = await pingWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PingResponse',) as PingResponse;
    
    }
    return null;
  }
}
