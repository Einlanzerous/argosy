//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DeviceRef {
  /// Returns a new [DeviceRef] instance.
  DeviceRef({
    required this.id,
    required this.name,
    this.platform,
  });

  String id;

  String name;

  /// web | phone | tv | ...
  String? platform;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeviceRef &&
    other.id == id &&
    other.name == name &&
    other.platform == platform;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (platform == null ? 0 : platform!.hashCode);

  @override
  String toString() => 'DeviceRef[id=$id, name=$name, platform=$platform]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
    if (this.platform != null) {
      json[r'platform'] = this.platform;
    } else {
      json[r'platform'] = null;
    }
    return json;
  }

  /// Returns a new [DeviceRef] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceRef? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "DeviceRef[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "DeviceRef[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "DeviceRef[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "DeviceRef[name]" has a null value in JSON.');
        return true;
      }());

      return DeviceRef(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        platform: mapValueOfType<String>(json, r'platform'),
      );
    }
    return null;
  }

  static List<DeviceRef> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DeviceRef>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceRef.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceRef> mapFromJson(dynamic json) {
    final map = <String, DeviceRef>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceRef.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceRef-objects as value to a dart map
  static Map<String, List<DeviceRef>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DeviceRef>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceRef.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
  };
}

