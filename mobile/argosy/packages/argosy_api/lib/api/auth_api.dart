//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class AuthApi {
  AuthApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Resolve the current (account, profile, device) from the token
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getCurrentSessionWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/me';

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

  /// Resolve the current (account, profile, device) from the token
  Future<Session?> getCurrentSession({ Future<void>? abortTrigger, }) async {
    final response = await getCurrentSessionWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Session',) as Session;
    
    }
    return null;
  }

  /// Get the calling device's playback preferences
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getDevicePreferencesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/preferences';

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

  /// Get the calling device's playback preferences
  Future<DevicePreferences?> getDevicePreferences({ Future<void>? abortTrigger, }) async {
    final response = await getDevicePreferencesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevicePreferences',) as DevicePreferences;
    
    }
    return null;
  }

  /// Get the calling profile's account-wide preferences
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getUserPreferencesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/user/preferences';

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

  /// Get the calling profile's account-wide preferences
  Future<UserPreferences?> getUserPreferences({ Future<void>? abortTrigger, }) async {
    final response = await getUserPreferencesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'UserPreferences',) as UserPreferences;
    
    }
    return null;
  }

  /// List devices in the current account (the Fleet)
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listDevicesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/devices';

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

  /// List devices in the current account (the Fleet)
  Future<List<Device>?> listDevices({ Future<void>? abortTrigger, }) async {
    final response = await listDevicesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<Device>') as List)
        .cast<Device>()
        .toList(growable: false);

    }
    return null;
  }

  /// Authenticate an account and list its profiles
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [LoginRequest] loginRequest (required):
  Future<Response> loginWithHttpInfo(LoginRequest loginRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/login';

    // ignore: prefer_final_locals
    Object? postBody = loginRequest;

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

  /// Authenticate an account and list its profiles
  ///
  /// Parameters:
  ///
  /// * [LoginRequest] loginRequest (required):
  Future<LoginResponse?> login(LoginRequest loginRequest, { Future<void>? abortTrigger, }) async {
    final response = await loginWithHttpInfo(loginRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'LoginResponse',) as LoginResponse;
    
    }
    return null;
  }

  /// Register a device for a profile and issue a device token
  ///
  /// Re-authenticates with account credentials and binds a new device to the chosen profile, returning a bearer token used for all subsequent calls. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DeviceRegistrationRequest] deviceRegistrationRequest (required):
  Future<Response> registerDeviceWithHttpInfo(DeviceRegistrationRequest deviceRegistrationRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/devices';

    // ignore: prefer_final_locals
    Object? postBody = deviceRegistrationRequest;

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

  /// Register a device for a profile and issue a device token
  ///
  /// Re-authenticates with account credentials and binds a new device to the chosen profile, returning a bearer token used for all subsequent calls. 
  ///
  /// Parameters:
  ///
  /// * [DeviceRegistrationRequest] deviceRegistrationRequest (required):
  Future<DeviceRegistrationResponse?> registerDevice(DeviceRegistrationRequest deviceRegistrationRequest, { Future<void>? abortTrigger, }) async {
    final response = await registerDeviceWithHttpInfo(deviceRegistrationRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DeviceRegistrationResponse',) as DeviceRegistrationResponse;
    
    }
    return null;
  }

  /// Rename a device in the Fleet
  ///
  /// Give a device a friendly label. Admins may rename any device in the account; a viewer may rename only their own. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [DeviceRenameRequest] deviceRenameRequest (required):
  Future<Response> renameDeviceWithHttpInfo(String deviceId, DeviceRenameRequest deviceRenameRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/devices/{deviceId}'
      .replaceAll('{deviceId}', deviceId);

    // ignore: prefer_final_locals
    Object? postBody = deviceRenameRequest;

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

  /// Rename a device in the Fleet
  ///
  /// Give a device a friendly label. Admins may rename any device in the account; a viewer may rename only their own. 
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [DeviceRenameRequest] deviceRenameRequest (required):
  Future<Device?> renameDevice(String deviceId, DeviceRenameRequest deviceRenameRequest, { Future<void>? abortTrigger, }) async {
    final response = await renameDeviceWithHttpInfo(deviceId, deviceRenameRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Device',) as Device;
    
    }
    return null;
  }

  /// Revoke a device token (\"retire from the Fleet\")
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  Future<Response> revokeDeviceWithHttpInfo(String deviceId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/devices/{deviceId}'
      .replaceAll('{deviceId}', deviceId);

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

  /// Revoke a device token (\"retire from the Fleet\")
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  Future<void> revokeDevice(String deviceId, { Future<void>? abortTrigger, }) async {
    final response = await revokeDeviceWithHttpInfo(deviceId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Update the calling device's playback preferences
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DevicePreferences] devicePreferences (required):
  Future<Response> setDevicePreferencesWithHttpInfo(DevicePreferences devicePreferences, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/preferences';

    // ignore: prefer_final_locals
    Object? postBody = devicePreferences;

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

  /// Update the calling device's playback preferences
  ///
  /// Parameters:
  ///
  /// * [DevicePreferences] devicePreferences (required):
  Future<DevicePreferences?> setDevicePreferences(DevicePreferences devicePreferences, { Future<void>? abortTrigger, }) async {
    final response = await setDevicePreferencesWithHttpInfo(devicePreferences, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevicePreferences',) as DevicePreferences;
    
    }
    return null;
  }

  /// Update the calling profile's account-wide preferences
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [UserPreferences] userPreferences (required):
  Future<Response> setUserPreferencesWithHttpInfo(UserPreferences userPreferences, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/user/preferences';

    // ignore: prefer_final_locals
    Object? postBody = userPreferences;

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

  /// Update the calling profile's account-wide preferences
  ///
  /// Parameters:
  ///
  /// * [UserPreferences] userPreferences (required):
  Future<UserPreferences?> setUserPreferences(UserPreferences userPreferences, { Future<void>? abortTrigger, }) async {
    final response = await setUserPreferencesWithHttpInfo(userPreferences, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'UserPreferences',) as UserPreferences;
    
    }
    return null;
  }
}
