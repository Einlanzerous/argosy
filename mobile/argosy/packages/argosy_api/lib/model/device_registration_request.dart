//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DeviceRegistrationRequest {
  /// Returns a new [DeviceRegistrationRequest] instance.
  DeviceRegistrationRequest({
    required this.email,
    this.username,
    required this.password,
    this.userId,
    this.newProfileName,
    required this.deviceName,
    this.platform,
    this.installId,
  });

  /// The account email (ARGY-159). Matched case-insensitively.
  String email;

  /// Legacy alias for `email`, honored so pre-ARGY-159 clients can still pair. Ignored when `email` is present.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? username;

  String password;

  /// The profile this device is bound to. Required unless the account has no profiles yet, in which case pass `newProfileName` instead.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? userId;

  /// First-login bootstrap (ARGY-159): create this profile (viewer role) and bind the device to it. Only honored while the account has zero profiles; mutually exclusive with `userId`.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? newProfileName;

  String deviceName;

  /// Client platform/type label (e.g. \"web\", \"tv\", \"phone\"); shown in the Fleet.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? platform;

  /// Stable per-install identifier the client persists across re-pairs. When present, a re-pair from the same physical device updates its existing Fleet row instead of creating a duplicate (ARGY-99). Omit to get a fresh device row each time.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? installId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeviceRegistrationRequest &&
    other.email == email &&
    other.username == username &&
    other.password == password &&
    other.userId == userId &&
    other.newProfileName == newProfileName &&
    other.deviceName == deviceName &&
    other.platform == platform &&
    other.installId == installId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (email.hashCode) +
    (username == null ? 0 : username!.hashCode) +
    (password.hashCode) +
    (userId == null ? 0 : userId!.hashCode) +
    (newProfileName == null ? 0 : newProfileName!.hashCode) +
    (deviceName.hashCode) +
    (platform == null ? 0 : platform!.hashCode) +
    (installId == null ? 0 : installId!.hashCode);

  @override
  String toString() => 'DeviceRegistrationRequest[email=$email, username=$username, password=$password, userId=$userId, newProfileName=$newProfileName, deviceName=$deviceName, platform=$platform, installId=$installId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'email'] = this.email;
    if (this.username != null) {
      json[r'username'] = this.username;
    } else {
      json[r'username'] = null;
    }
      json[r'password'] = this.password;
    if (this.userId != null) {
      json[r'userId'] = this.userId;
    } else {
      json[r'userId'] = null;
    }
    if (this.newProfileName != null) {
      json[r'newProfileName'] = this.newProfileName;
    } else {
      json[r'newProfileName'] = null;
    }
      json[r'deviceName'] = this.deviceName;
    if (this.platform != null) {
      json[r'platform'] = this.platform;
    } else {
      json[r'platform'] = null;
    }
    if (this.installId != null) {
      json[r'installId'] = this.installId;
    } else {
      json[r'installId'] = null;
    }
    return json;
  }

  /// Returns a new [DeviceRegistrationRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceRegistrationRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'email'), 'Required key "DeviceRegistrationRequest[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "DeviceRegistrationRequest[email]" has a null value in JSON.');
        assert(json.containsKey(r'password'), 'Required key "DeviceRegistrationRequest[password]" is missing from JSON.');
        assert(json[r'password'] != null, 'Required key "DeviceRegistrationRequest[password]" has a null value in JSON.');
        assert(json.containsKey(r'deviceName'), 'Required key "DeviceRegistrationRequest[deviceName]" is missing from JSON.');
        assert(json[r'deviceName'] != null, 'Required key "DeviceRegistrationRequest[deviceName]" has a null value in JSON.');
        return true;
      }());

      return DeviceRegistrationRequest(
        email: mapValueOfType<String>(json, r'email')!,
        username: mapValueOfType<String>(json, r'username'),
        password: mapValueOfType<String>(json, r'password')!,
        userId: mapValueOfType<String>(json, r'userId'),
        newProfileName: mapValueOfType<String>(json, r'newProfileName'),
        deviceName: mapValueOfType<String>(json, r'deviceName')!,
        platform: mapValueOfType<String>(json, r'platform'),
        installId: mapValueOfType<String>(json, r'installId'),
      );
    }
    return null;
  }

  static List<DeviceRegistrationRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DeviceRegistrationRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceRegistrationRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceRegistrationRequest> mapFromJson(dynamic json) {
    final map = <String, DeviceRegistrationRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceRegistrationRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceRegistrationRequest-objects as value to a dart map
  static Map<String, List<DeviceRegistrationRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DeviceRegistrationRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceRegistrationRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'email',
    'password',
    'deviceName',
  };
}

