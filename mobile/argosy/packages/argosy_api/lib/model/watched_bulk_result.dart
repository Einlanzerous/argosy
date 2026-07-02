//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WatchedBulkResult {
  /// Returns a new [WatchedBulkResult] instance.
  WatchedBulkResult({
    required this.updated,
  });

  /// Backing files whose watched state was written.
  int updated;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WatchedBulkResult &&
    other.updated == updated;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (updated.hashCode);

  @override
  String toString() => 'WatchedBulkResult[updated=$updated]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'updated'] = this.updated;
    return json;
  }

  /// Returns a new [WatchedBulkResult] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static WatchedBulkResult? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'updated'), 'Required key "WatchedBulkResult[updated]" is missing from JSON.');
        assert(json[r'updated'] != null, 'Required key "WatchedBulkResult[updated]" has a null value in JSON.');
        return true;
      }());

      return WatchedBulkResult(
        updated: mapValueOfType<int>(json, r'updated')!,
      );
    }
    return null;
  }

  static List<WatchedBulkResult> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WatchedBulkResult>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WatchedBulkResult.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WatchedBulkResult> mapFromJson(dynamic json) {
    final map = <String, WatchedBulkResult>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WatchedBulkResult.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of WatchedBulkResult-objects as value to a dart map
  static Map<String, List<WatchedBulkResult>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WatchedBulkResult>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WatchedBulkResult.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'updated',
  };
}

