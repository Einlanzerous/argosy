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

  /// Approve a pairing code from a signed-in session
  ///
  /// Called from an authenticated session (web or mobile). Links the new device to the caller's account and profile by creating a device; the new device claims its token on the next poll. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] code (required):
  ///
  /// * [LinkApproveRequest] linkApproveRequest:
  Future<Response> approveLinkWithHttpInfo(String code, { LinkApproveRequest? linkApproveRequest, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/link/{code}/approve'
      .replaceAll('{code}', code);

    // ignore: prefer_final_locals
    Object? postBody = linkApproveRequest;

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

  /// Approve a pairing code from a signed-in session
  ///
  /// Called from an authenticated session (web or mobile). Links the new device to the caller's account and profile by creating a device; the new device claims its token on the next poll. 
  ///
  /// Parameters:
  ///
  /// * [String] code (required):
  ///
  /// * [LinkApproveRequest] linkApproveRequest:
  Future<void> approveLink(String code, { LinkApproveRequest? linkApproveRequest, Future<void>? abortTrigger, }) async {
    final response = await approveLinkWithHttpInfo(code, linkApproveRequest: linkApproveRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Change the account password (self-serve)
  ///
  /// Verifies the current account password and replaces it with a new one. Device tokens are independent of the password, so existing devices stay signed in. A wrong current password answers 403 (never 401 — it must not look like an expired token and sign the device out). 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PasswordChangeRequest] passwordChangeRequest (required):
  Future<Response> changePasswordWithHttpInfo(PasswordChangeRequest passwordChangeRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/password';

    // ignore: prefer_final_locals
    Object? postBody = passwordChangeRequest;

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

  /// Change the account password (self-serve)
  ///
  /// Verifies the current account password and replaces it with a new one. Device tokens are independent of the password, so existing devices stay signed in. A wrong current password answers 403 (never 401 — it must not look like an expired token and sign the device out). 
  ///
  /// Parameters:
  ///
  /// * [PasswordChangeRequest] passwordChangeRequest (required):
  Future<void> changePassword(PasswordChangeRequest passwordChangeRequest, { Future<void>? abortTrigger, }) async {
    final response = await changePasswordWithHttpInfo(passwordChangeRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Create an account (service-to-service provisioning)
  ///
  /// Creates a new account with one initial admin profile named after the account. This is the Purser provisioning surface (ARGY-132): it is authorized by the static X-Provision-Token header rather than a bearer session, because a session is always scoped to an *existing* account. When `password` is omitted the server generates one and returns it exactly once as `generatedPassword` — only the bcrypt hash is stored. The route is registered only when ARGOSY_PROVISION_TOKEN is set, so an unconfigured server answers 404. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AccountCreateRequest] accountCreateRequest (required):
  Future<Response> createAccountWithHttpInfo(AccountCreateRequest accountCreateRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/admin/accounts';

    // ignore: prefer_final_locals
    Object? postBody = accountCreateRequest;

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

  /// Create an account (service-to-service provisioning)
  ///
  /// Creates a new account with one initial admin profile named after the account. This is the Purser provisioning surface (ARGY-132): it is authorized by the static X-Provision-Token header rather than a bearer session, because a session is always scoped to an *existing* account. When `password` is omitted the server generates one and returns it exactly once as `generatedPassword` — only the bcrypt hash is stored. The route is registered only when ARGOSY_PROVISION_TOKEN is set, so an unconfigured server answers 404. 
  ///
  /// Parameters:
  ///
  /// * [AccountCreateRequest] accountCreateRequest (required):
  Future<AccountCreateResponse?> createAccount(AccountCreateRequest accountCreateRequest, { Future<void>? abortTrigger, }) async {
    final response = await createAccountWithHttpInfo(accountCreateRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AccountCreateResponse',) as AccountCreateResponse;
    
    }
    return null;
  }

  /// Create a profile (admin only)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ProfileCreateRequest] profileCreateRequest (required):
  Future<Response> createProfileWithHttpInfo(ProfileCreateRequest profileCreateRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/profiles';

    // ignore: prefer_final_locals
    Object? postBody = profileCreateRequest;

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

  /// Create a profile (admin only)
  ///
  /// Parameters:
  ///
  /// * [ProfileCreateRequest] profileCreateRequest (required):
  Future<ProfileSummary?> createProfile(ProfileCreateRequest profileCreateRequest, { Future<void>? abortTrigger, }) async {
    final response = await createProfileWithHttpInfo(profileCreateRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ProfileSummary',) as ProfileSummary;
    
    }
    return null;
  }

  /// Delete an account and everything it owns (owner only)
  ///
  /// Removes the account with its profiles, devices, watch history, vaults and preferences (DB cascade). The instance owner's account can't be deleted, and neither can an account that still owns media libraries (possible on pre-ARGY-167 data) — the cascade would take catalog items with it, so such rows must be moved first. Prefer disabling unless the person is truly gone — deletion is unrecoverable. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  Future<Response> deleteAccountWithHttpInfo(String accountId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/accounts/{accountId}'
      .replaceAll('{accountId}', accountId);

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

  /// Delete an account and everything it owns (owner only)
  ///
  /// Removes the account with its profiles, devices, watch history, vaults and preferences (DB cascade). The instance owner's account can't be deleted, and neither can an account that still owns media libraries (possible on pre-ARGY-167 data) — the cascade would take catalog items with it, so such rows must be moved first. Prefer disabling unless the person is truly gone — deletion is unrecoverable. 
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  Future<void> deleteAccount(String accountId, { Future<void>? abortTrigger, }) async {
    final response = await deleteAccountWithHttpInfo(accountId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Delete a profile (admin only)
  ///
  /// Devices bound to the deleted profile are unbound — they keep working but drop to viewer access until reassigned. The account must keep at least one admin, and you can't delete the profile you're currently signed in as. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] userId (required):
  Future<Response> deleteProfileWithHttpInfo(String userId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/profiles/{userId}'
      .replaceAll('{userId}', userId);

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

  /// Delete a profile (admin only)
  ///
  /// Devices bound to the deleted profile are unbound — they keep working but drop to viewer access until reassigned. The account must keep at least one admin, and you can't delete the profile you're currently signed in as. 
  ///
  /// Parameters:
  ///
  /// * [String] userId (required):
  Future<void> deleteProfile(String userId, { Future<void>? abortTrigger, }) async {
    final response = await deleteProfileWithHttpInfo(userId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Delete an account by email (service-to-service deprovisioning)
  ///
  /// The teardown companion to createAccount (ARGY-86): lets the provisioning service remove the account it created when a member is offboarded, taking profiles, devices, history and preferences with it (DB cascade). The instance owner's account is refused with 409. Gated on the same X-Provision-Token, and registered only when ARGOSY_PROVISION_TOKEN is set. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] email (required):
  ///   The account email. Matched case-insensitively.
  Future<Response> deprovisionAccountWithHttpInfo(String email, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/admin/accounts';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

      queryParams.addAll(_queryParams('', 'email', email));

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

  /// Delete an account by email (service-to-service deprovisioning)
  ///
  /// The teardown companion to createAccount (ARGY-86): lets the provisioning service remove the account it created when a member is offboarded, taking profiles, devices, history and preferences with it (DB cascade). The instance owner's account is refused with 409. Gated on the same X-Provision-Token, and registered only when ARGOSY_PROVISION_TOKEN is set. 
  ///
  /// Parameters:
  ///
  /// * [String] email (required):
  ///   The account email. Matched case-insensitively.
  Future<void> deprovisionAccount(String email, { Future<void>? abortTrigger, }) async {
    final response = await deprovisionAccountWithHttpInfo(email, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

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

  /// Poll a pairing code; returns the device token once approved
  ///
  /// The new device polls this. While pending, `status` is `pending`. Once approved, it returns `status: approved` plus the one-time device `token`, and the code is consumed (single use). While pending it also echoes the device-announced `deviceName`/`platform` so an approving UI can show what is about to be linked. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] code (required):
  Future<Response> getLinkStatusWithHttpInfo(String code, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/link/{code}'
      .replaceAll('{code}', code);

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

  /// Poll a pairing code; returns the device token once approved
  ///
  /// The new device polls this. While pending, `status` is `pending`. Once approved, it returns `status: approved` plus the one-time device `token`, and the code is consumed (single use). While pending it also echoes the device-announced `deviceName`/`platform` so an approving UI can show what is about to be linked. 
  ///
  /// Parameters:
  ///
  /// * [String] code (required):
  Future<LinkStatusResponse?> getLinkStatus(String code, { Future<void>? abortTrigger, }) async {
    final response = await getLinkStatusWithHttpInfo(code, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'LinkStatusResponse',) as LinkStatusResponse;
    
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

  /// List every account on this instance (owner only)
  ///
  /// Account lifecycle surface (ARGY-86). Listing and managing *accounts* is an instance-level power — accounts are the server's households, not anything inside the caller's own — so it is gated on instance ownership (ARGY-167), not household admin. 
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listAccountsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/accounts';

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

  /// List every account on this instance (owner only)
  ///
  /// Account lifecycle surface (ARGY-86). Listing and managing *accounts* is an instance-level power — accounts are the server's households, not anything inside the caller's own — so it is gated on instance ownership (ARGY-167), not household admin. 
  Future<List<AccountSummary>?> listAccounts({ Future<void>? abortTrigger, }) async {
    final response = await listAccountsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<AccountSummary>') as List)
        .cast<AccountSummary>()
        .toList(growable: false);

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

  /// List the current account's profiles
  ///
  /// Returns every profile in the caller's account with its role and how many active devices are bound to it. Any signed-in profile may list; creating, editing, and deleting profiles is admin-only. 
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listProfilesWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/profiles';

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

  /// List the current account's profiles
  ///
  /// Returns every profile in the caller's account with its role and how many active devices are bound to it. Any signed-in profile may list; creating, editing, and deleting profiles is admin-only. 
  Future<List<ProfileSummary>?> listProfiles({ Future<void>? abortTrigger, }) async {
    final response = await listProfilesWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<ProfileSummary>') as List)
        .cast<ProfileSummary>()
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

  /// Look up an account by email (service-to-service provisioning)
  ///
  /// Read-only companion to createAccount (ARGY-163): answers whether an account exists for the given email without creating or changing anything, so a reconcile pass can run record-only. Gated on the same X-Provision-Token, and registered only when ARGOSY_PROVISION_TOKEN is set. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] email (required):
  ///   The account email. Matched case-insensitively.
  Future<Response> lookupAccountWithHttpInfo(String email, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/admin/accounts';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

      queryParams.addAll(_queryParams('', 'email', email));

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

  /// Look up an account by email (service-to-service provisioning)
  ///
  /// Read-only companion to createAccount (ARGY-163): answers whether an account exists for the given email without creating or changing anything, so a reconcile pass can run record-only. Gated on the same X-Provision-Token, and registered only when ARGOSY_PROVISION_TOKEN is set. 
  ///
  /// Parameters:
  ///
  /// * [String] email (required):
  ///   The account email. Matched case-insensitively.
  Future<AccountLookupResponse?> lookupAccount(String email, { Future<void>? abortTrigger, }) async {
    final response = await lookupAccountWithHttpInfo(email, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AccountLookupResponse',) as AccountLookupResponse;
    
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

  /// Reset an account's password to a fresh generated one (owner only)
  ///
  /// Server-generates a new password and returns it exactly once — the same contract as provisioning (only the bcrypt hash is stored). There is no way to *choose* a password for someone else. The account's paired devices are revoked as part of the reset: unlike the self-serve change-password flow (which proves the current password, so existing devices are known-good), an owner reset means the credential was lost or leaked, and a leaked password may already have paired a device. The owner account itself is refused: rotate your own password through the self-serve flow instead. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  Future<Response> resetAccountPasswordWithHttpInfo(String accountId, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/accounts/{accountId}/password-reset'
      .replaceAll('{accountId}', accountId);

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

  /// Reset an account's password to a fresh generated one (owner only)
  ///
  /// Server-generates a new password and returns it exactly once — the same contract as provisioning (only the bcrypt hash is stored). There is no way to *choose* a password for someone else. The account's paired devices are revoked as part of the reset: unlike the self-serve change-password flow (which proves the current password, so existing devices are known-good), an owner reset means the credential was lost or leaked, and a leaked password may already have paired a device. The owner account itself is refused: rotate your own password through the self-serve flow instead. 
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  Future<PasswordResetResponse?> resetAccountPassword(String accountId, { Future<void>? abortTrigger, }) async {
    final response = await resetAccountPasswordWithHttpInfo(accountId, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PasswordResetResponse',) as PasswordResetResponse;
    
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

  /// Begin code-pairing — mint a short code for the new device to display
  ///
  /// A new device (TV or phone, which shouldn't have to type credentials) calls this to get a short pairing code. It displays the code, then polls `GET /auth/link/{code}` until an authenticated user approves it and a device token is handed back. The optional body lets the device announce what it is, so the approver sees \"Pixel 9 (android)\" instead of a bare code and the created Fleet device is named/typed correctly. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [LinkStartRequest] linkStartRequest:
  Future<Response> startLinkWithHttpInfo({ LinkStartRequest? linkStartRequest, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/link/start';

    // ignore: prefer_final_locals
    Object? postBody = linkStartRequest;

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

  /// Begin code-pairing — mint a short code for the new device to display
  ///
  /// A new device (TV or phone, which shouldn't have to type credentials) calls this to get a short pairing code. It displays the code, then polls `GET /auth/link/{code}` until an authenticated user approves it and a device token is handed back. The optional body lets the device announce what it is, so the approver sees \"Pixel 9 (android)\" instead of a bare code and the created Fleet device is named/typed correctly. 
  ///
  /// Parameters:
  ///
  /// * [LinkStartRequest] linkStartRequest:
  Future<LinkStartResponse?> startLink({ LinkStartRequest? linkStartRequest, Future<void>? abortTrigger, }) async {
    final response = await startLinkWithHttpInfo(linkStartRequest: linkStartRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'LinkStartResponse',) as LinkStartResponse;
    
    }
    return null;
  }

  /// Re-bind the calling device to another profile (in-place switch)
  ///
  /// Re-points the calling device to a different profile in the same account without re-pairing — the device token is unchanged. Switching INTO an admin profile requires the account password so a viewer device can't silently assume admin. Returns the refreshed session. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DeviceSwitchRequest] deviceSwitchRequest (required):
  Future<Response> switchDeviceProfileWithHttpInfo(DeviceSwitchRequest deviceSwitchRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/devices/switch';

    // ignore: prefer_final_locals
    Object? postBody = deviceSwitchRequest;

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

  /// Re-bind the calling device to another profile (in-place switch)
  ///
  /// Re-points the calling device to a different profile in the same account without re-pairing — the device token is unchanged. Switching INTO an admin profile requires the account password so a viewer device can't silently assume admin. Returns the refreshed session. 
  ///
  /// Parameters:
  ///
  /// * [DeviceSwitchRequest] deviceSwitchRequest (required):
  Future<Session?> switchDeviceProfile(DeviceSwitchRequest deviceSwitchRequest, { Future<void>? abortTrigger, }) async {
    final response = await switchDeviceProfileWithHttpInfo(deviceSwitchRequest, abortTrigger: abortTrigger,);
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

  /// Disable or re-enable an account (owner only)
  ///
  /// A disabled account keeps all its data but can no longer sign in, and its paired devices stop authenticating immediately. The instance owner's account can't be disabled — that would brick the server. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  ///
  /// * [AccountUpdateRequest] accountUpdateRequest (required):
  Future<Response> updateAccountWithHttpInfo(String accountId, AccountUpdateRequest accountUpdateRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/accounts/{accountId}'
      .replaceAll('{accountId}', accountId);

    // ignore: prefer_final_locals
    Object? postBody = accountUpdateRequest;

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

  /// Disable or re-enable an account (owner only)
  ///
  /// A disabled account keeps all its data but can no longer sign in, and its paired devices stop authenticating immediately. The instance owner's account can't be disabled — that would brick the server. 
  ///
  /// Parameters:
  ///
  /// * [String] accountId (required):
  ///
  /// * [AccountUpdateRequest] accountUpdateRequest (required):
  Future<AccountSummary?> updateAccount(String accountId, AccountUpdateRequest accountUpdateRequest, { Future<void>? abortTrigger, }) async {
    final response = await updateAccountWithHttpInfo(accountId, accountUpdateRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AccountSummary',) as AccountSummary;
    
    }
    return null;
  }

  /// Rename a profile or change its role (admin only)
  ///
  /// Omit a field to leave it unchanged. Demoting the only remaining admin to viewer is rejected so an account can never lock itself out. 
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] userId (required):
  ///
  /// * [ProfileUpdateRequest] profileUpdateRequest (required):
  Future<Response> updateProfileWithHttpInfo(String userId, ProfileUpdateRequest profileUpdateRequest, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/profiles/{userId}'
      .replaceAll('{userId}', userId);

    // ignore: prefer_final_locals
    Object? postBody = profileUpdateRequest;

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

  /// Rename a profile or change its role (admin only)
  ///
  /// Omit a field to leave it unchanged. Demoting the only remaining admin to viewer is rejected so an account can never lock itself out. 
  ///
  /// Parameters:
  ///
  /// * [String] userId (required):
  ///
  /// * [ProfileUpdateRequest] profileUpdateRequest (required):
  Future<ProfileSummary?> updateProfile(String userId, ProfileUpdateRequest profileUpdateRequest, { Future<void>? abortTrigger, }) async {
    final response = await updateProfileWithHttpInfo(userId, profileUpdateRequest, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ProfileSummary',) as ProfileSummary;
    
    }
    return null;
  }
}
