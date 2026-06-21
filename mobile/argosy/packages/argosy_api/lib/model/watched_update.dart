//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WatchedUpdate {
  /// Returns a new [WatchedUpdate] instance.
  WatchedUpdate({
    required this.watched,
  });

  bool watched;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WatchedUpdate &&
    other.watched == watched;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (watched.hashCode);

  @override
  String toString() => 'WatchedUpdate[watched=$watched]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'watched'] = this.watched;
    return json;
  }

  /// Returns a new [WatchedUpdate] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static WatchedUpdate? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'watched'), 'Required key "WatchedUpdate[watched]" is missing from JSON.');
        assert(json[r'watched'] != null, 'Required key "WatchedUpdate[watched]" has a null value in JSON.');
        return true;
      }());

      return WatchedUpdate(
        watched: mapValueOfType<bool>(json, r'watched')!,
      );
    }
    return null;
  }

  static List<WatchedUpdate> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WatchedUpdate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WatchedUpdate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WatchedUpdate> mapFromJson(dynamic json) {
    final map = <String, WatchedUpdate>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WatchedUpdate.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of WatchedUpdate-objects as value to a dart map
  static Map<String, List<WatchedUpdate>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WatchedUpdate>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WatchedUpdate.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'watched',
  };
}

