//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Device {
  /// Returns a new [Device] instance.
  Device({
    required this.id,
    required this.name,
    this.platform,
    required this.userId,
    this.userName,
    this.lastSeenAt,
    required this.revoked,
    required this.createdAt,
  });

  String id;

  String name;

  /// Client platform/type label captured at registration.
  String? platform;

  String? userId;

  /// Display name of the profile this device is bound to (the Fleet shows whose device it is).
  String? userName;

  DateTime? lastSeenAt;

  bool revoked;

  DateTime createdAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Device &&
    other.id == id &&
    other.name == name &&
    other.platform == platform &&
    other.userId == userId &&
    other.userName == userName &&
    other.lastSeenAt == lastSeenAt &&
    other.revoked == revoked &&
    other.createdAt == createdAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (platform == null ? 0 : platform!.hashCode) +
    (userId == null ? 0 : userId!.hashCode) +
    (userName == null ? 0 : userName!.hashCode) +
    (lastSeenAt == null ? 0 : lastSeenAt!.hashCode) +
    (revoked.hashCode) +
    (createdAt.hashCode);

  @override
  String toString() => 'Device[id=$id, name=$name, platform=$platform, userId=$userId, userName=$userName, lastSeenAt=$lastSeenAt, revoked=$revoked, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
    if (this.platform != null) {
      json[r'platform'] = this.platform;
    } else {
      json[r'platform'] = null;
    }
    if (this.userId != null) {
      json[r'userId'] = this.userId;
    } else {
      json[r'userId'] = null;
    }
    if (this.userName != null) {
      json[r'userName'] = this.userName;
    } else {
      json[r'userName'] = null;
    }
    if (this.lastSeenAt != null) {
      json[r'lastSeenAt'] = this.lastSeenAt!.toUtc().toIso8601String();
    } else {
      json[r'lastSeenAt'] = null;
    }
      json[r'revoked'] = this.revoked;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [Device] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Device? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Device[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Device[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "Device[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "Device[name]" has a null value in JSON.');
        assert(json.containsKey(r'userId'), 'Required key "Device[userId]" is missing from JSON.');
        assert(json.containsKey(r'revoked'), 'Required key "Device[revoked]" is missing from JSON.');
        assert(json[r'revoked'] != null, 'Required key "Device[revoked]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "Device[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "Device[createdAt]" has a null value in JSON.');
        return true;
      }());

      return Device(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        platform: mapValueOfType<String>(json, r'platform'),
        userId: mapValueOfType<String>(json, r'userId'),
        userName: mapValueOfType<String>(json, r'userName'),
        lastSeenAt: mapDateTime(json, r'lastSeenAt', r''),
        revoked: mapValueOfType<bool>(json, r'revoked')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<Device> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Device>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Device.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Device> mapFromJson(dynamic json) {
    final map = <String, Device>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Device.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Device-objects as value to a dart map
  static Map<String, List<Device>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Device>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Device.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
    'userId',
    'revoked',
    'createdAt',
  };
}

