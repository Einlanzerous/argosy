//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ProgressUpdate {
  /// Returns a new [ProgressUpdate] instance.
  ProgressUpdate({
    required this.positionSeconds,
    this.durationSeconds,
  });

  num positionSeconds;

  num? durationSeconds;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ProgressUpdate &&
    other.positionSeconds == positionSeconds &&
    other.durationSeconds == durationSeconds;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (positionSeconds.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode);

  @override
  String toString() => 'ProgressUpdate[positionSeconds=$positionSeconds, durationSeconds=$durationSeconds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'positionSeconds'] = this.positionSeconds;
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
    return json;
  }

  /// Returns a new [ProgressUpdate] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ProgressUpdate? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'positionSeconds'), 'Required key "ProgressUpdate[positionSeconds]" is missing from JSON.');
        assert(json[r'positionSeconds'] != null, 'Required key "ProgressUpdate[positionSeconds]" has a null value in JSON.');
        return true;
      }());

      return ProgressUpdate(
        positionSeconds: num.parse('${json[r'positionSeconds']}'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
      );
    }
    return null;
  }

  static List<ProgressUpdate> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ProgressUpdate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ProgressUpdate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ProgressUpdate> mapFromJson(dynamic json) {
    final map = <String, ProgressUpdate>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ProgressUpdate.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ProgressUpdate-objects as value to a dart map
  static Map<String, List<ProgressUpdate>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ProgressUpdate>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ProgressUpdate.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'positionSeconds',
  };
}

