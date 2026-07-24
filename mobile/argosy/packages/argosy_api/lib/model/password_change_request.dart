//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PasswordChangeRequest {
  /// Returns a new [PasswordChangeRequest] instance.
  PasswordChangeRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  String currentPassword;

  String newPassword;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PasswordChangeRequest &&
    other.currentPassword == currentPassword &&
    other.newPassword == newPassword;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (currentPassword.hashCode) +
    (newPassword.hashCode);

  @override
  String toString() => 'PasswordChangeRequest[currentPassword=$currentPassword, newPassword=$newPassword]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'currentPassword'] = this.currentPassword;
      json[r'newPassword'] = this.newPassword;
    return json;
  }

  /// Returns a new [PasswordChangeRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PasswordChangeRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'currentPassword'), 'Required key "PasswordChangeRequest[currentPassword]" is missing from JSON.');
        assert(json[r'currentPassword'] != null, 'Required key "PasswordChangeRequest[currentPassword]" has a null value in JSON.');
        assert(json.containsKey(r'newPassword'), 'Required key "PasswordChangeRequest[newPassword]" is missing from JSON.');
        assert(json[r'newPassword'] != null, 'Required key "PasswordChangeRequest[newPassword]" has a null value in JSON.');
        return true;
      }());

      return PasswordChangeRequest(
        currentPassword: mapValueOfType<String>(json, r'currentPassword')!,
        newPassword: mapValueOfType<String>(json, r'newPassword')!,
      );
    }
    return null;
  }

  static List<PasswordChangeRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PasswordChangeRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PasswordChangeRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PasswordChangeRequest> mapFromJson(dynamic json) {
    final map = <String, PasswordChangeRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PasswordChangeRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PasswordChangeRequest-objects as value to a dart map
  static Map<String, List<PasswordChangeRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PasswordChangeRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PasswordChangeRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'currentPassword',
    'newPassword',
  };
}

