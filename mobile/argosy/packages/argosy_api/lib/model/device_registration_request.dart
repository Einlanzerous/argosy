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
    required this.username,
    required this.password,
    required this.userId,
    required this.deviceName,
    this.platform,
  });

  String username;

  String password;

  /// The profile this device is bound to.
  String userId;

  String deviceName;

  /// Client platform/type label (e.g. \"web\", \"tv\", \"phone\"); shown in the Fleet.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? platform;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeviceRegistrationRequest &&
    other.username == username &&
    other.password == password &&
    other.userId == userId &&
    other.deviceName == deviceName &&
    other.platform == platform;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (username.hashCode) +
    (password.hashCode) +
    (userId.hashCode) +
    (deviceName.hashCode) +
    (platform == null ? 0 : platform!.hashCode);

  @override
  String toString() => 'DeviceRegistrationRequest[username=$username, password=$password, userId=$userId, deviceName=$deviceName, platform=$platform]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'username'] = this.username;
      json[r'password'] = this.password;
      json[r'userId'] = this.userId;
      json[r'deviceName'] = this.deviceName;
    if (this.platform != null) {
      json[r'platform'] = this.platform;
    } else {
      json[r'platform'] = null;
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
        assert(json.containsKey(r'username'), 'Required key "DeviceRegistrationRequest[username]" is missing from JSON.');
        assert(json[r'username'] != null, 'Required key "DeviceRegistrationRequest[username]" has a null value in JSON.');
        assert(json.containsKey(r'password'), 'Required key "DeviceRegistrationRequest[password]" is missing from JSON.');
        assert(json[r'password'] != null, 'Required key "DeviceRegistrationRequest[password]" has a null value in JSON.');
        assert(json.containsKey(r'userId'), 'Required key "DeviceRegistrationRequest[userId]" is missing from JSON.');
        assert(json[r'userId'] != null, 'Required key "DeviceRegistrationRequest[userId]" has a null value in JSON.');
        assert(json.containsKey(r'deviceName'), 'Required key "DeviceRegistrationRequest[deviceName]" is missing from JSON.');
        assert(json[r'deviceName'] != null, 'Required key "DeviceRegistrationRequest[deviceName]" has a null value in JSON.');
        return true;
      }());

      return DeviceRegistrationRequest(
        username: mapValueOfType<String>(json, r'username')!,
        password: mapValueOfType<String>(json, r'password')!,
        userId: mapValueOfType<String>(json, r'userId')!,
        deviceName: mapValueOfType<String>(json, r'deviceName')!,
        platform: mapValueOfType<String>(json, r'platform'),
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
    'username',
    'password',
    'userId',
    'deviceName',
  };
}

