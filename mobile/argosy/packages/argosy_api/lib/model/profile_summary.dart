//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ProfileSummary {
  /// Returns a new [ProfileSummary] instance.
  ProfileSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.deviceCount,
  });

  String id;

  String name;

  Role role;

  /// Number of active (non-revoked) devices currently bound to this profile.
  int deviceCount;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ProfileSummary &&
    other.id == id &&
    other.name == name &&
    other.role == role &&
    other.deviceCount == deviceCount;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (role.hashCode) +
    (deviceCount.hashCode);

  @override
  String toString() => 'ProfileSummary[id=$id, name=$name, role=$role, deviceCount=$deviceCount]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
      json[r'role'] = this.role;
      json[r'deviceCount'] = this.deviceCount;
    return json;
  }

  /// Returns a new [ProfileSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ProfileSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "ProfileSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "ProfileSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "ProfileSummary[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ProfileSummary[name]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "ProfileSummary[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "ProfileSummary[role]" has a null value in JSON.');
        assert(json.containsKey(r'deviceCount'), 'Required key "ProfileSummary[deviceCount]" is missing from JSON.');
        assert(json[r'deviceCount'] != null, 'Required key "ProfileSummary[deviceCount]" has a null value in JSON.');
        return true;
      }());

      return ProfileSummary(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        role: Role.fromJson(json[r'role'])!,
        deviceCount: mapValueOfType<int>(json, r'deviceCount')!,
      );
    }
    return null;
  }

  static List<ProfileSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ProfileSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ProfileSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ProfileSummary> mapFromJson(dynamic json) {
    final map = <String, ProfileSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ProfileSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ProfileSummary-objects as value to a dart map
  static Map<String, List<ProfileSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ProfileSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ProfileSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
    'role',
    'deviceCount',
  };
}

