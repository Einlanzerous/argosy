//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ProfileCreateRequest {
  /// Returns a new [ProfileCreateRequest] instance.
  ProfileCreateRequest({
    required this.name,
    required this.role,
  });

  String name;

  Role role;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ProfileCreateRequest &&
    other.name == name &&
    other.role == role;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (role.hashCode);

  @override
  String toString() => 'ProfileCreateRequest[name=$name, role=$role]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
      json[r'role'] = this.role;
    return json;
  }

  /// Returns a new [ProfileCreateRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ProfileCreateRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'name'), 'Required key "ProfileCreateRequest[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ProfileCreateRequest[name]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "ProfileCreateRequest[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "ProfileCreateRequest[role]" has a null value in JSON.');
        return true;
      }());

      return ProfileCreateRequest(
        name: mapValueOfType<String>(json, r'name')!,
        role: Role.fromJson(json[r'role'])!,
      );
    }
    return null;
  }

  static List<ProfileCreateRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ProfileCreateRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ProfileCreateRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ProfileCreateRequest> mapFromJson(dynamic json) {
    final map = <String, ProfileCreateRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ProfileCreateRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ProfileCreateRequest-objects as value to a dart map
  static Map<String, List<ProfileCreateRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ProfileCreateRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ProfileCreateRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'name',
    'role',
  };
}

