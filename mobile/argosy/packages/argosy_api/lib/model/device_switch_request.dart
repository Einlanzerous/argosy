//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DeviceSwitchRequest {
  /// Returns a new [DeviceSwitchRequest] instance.
  DeviceSwitchRequest({
    required this.userId,
    this.password,
  });

  /// The profile (in the same account) to bind this device to.
  String userId;

  /// Account password. Required only when switching INTO an admin profile; ignored for viewer targets.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? password;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeviceSwitchRequest &&
    other.userId == userId &&
    other.password == password;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (userId.hashCode) +
    (password == null ? 0 : password!.hashCode);

  @override
  String toString() => 'DeviceSwitchRequest[userId=$userId, password=$password]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'userId'] = this.userId;
    if (this.password != null) {
      json[r'password'] = this.password;
    } else {
      json[r'password'] = null;
    }
    return json;
  }

  /// Returns a new [DeviceSwitchRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceSwitchRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'userId'), 'Required key "DeviceSwitchRequest[userId]" is missing from JSON.');
        assert(json[r'userId'] != null, 'Required key "DeviceSwitchRequest[userId]" has a null value in JSON.');
        return true;
      }());

      return DeviceSwitchRequest(
        userId: mapValueOfType<String>(json, r'userId')!,
        password: mapValueOfType<String>(json, r'password'),
      );
    }
    return null;
  }

  static List<DeviceSwitchRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DeviceSwitchRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceSwitchRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceSwitchRequest> mapFromJson(dynamic json) {
    final map = <String, DeviceSwitchRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceSwitchRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceSwitchRequest-objects as value to a dart map
  static Map<String, List<DeviceSwitchRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DeviceSwitchRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceSwitchRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'userId',
  };
}

