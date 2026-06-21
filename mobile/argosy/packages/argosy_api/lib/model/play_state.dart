//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PlayState {
  /// Returns a new [PlayState] instance.
  PlayState({
    required this.positionSeconds,
    this.durationSeconds,
    required this.watched,
    this.updatedAt,
  });

  num positionSeconds;

  num? durationSeconds;

  bool watched;

  DateTime? updatedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PlayState &&
    other.positionSeconds == positionSeconds &&
    other.durationSeconds == durationSeconds &&
    other.watched == watched &&
    other.updatedAt == updatedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (positionSeconds.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (watched.hashCode) +
    (updatedAt == null ? 0 : updatedAt!.hashCode);

  @override
  String toString() => 'PlayState[positionSeconds=$positionSeconds, durationSeconds=$durationSeconds, watched=$watched, updatedAt=$updatedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'positionSeconds'] = this.positionSeconds;
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
      json[r'watched'] = this.watched;
    if (this.updatedAt != null) {
      json[r'updatedAt'] = this.updatedAt!.toUtc().toIso8601String();
    } else {
      json[r'updatedAt'] = null;
    }
    return json;
  }

  /// Returns a new [PlayState] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PlayState? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'positionSeconds'), 'Required key "PlayState[positionSeconds]" is missing from JSON.');
        assert(json[r'positionSeconds'] != null, 'Required key "PlayState[positionSeconds]" has a null value in JSON.');
        assert(json.containsKey(r'watched'), 'Required key "PlayState[watched]" is missing from JSON.');
        assert(json[r'watched'] != null, 'Required key "PlayState[watched]" has a null value in JSON.');
        return true;
      }());

      return PlayState(
        positionSeconds: num.parse('${json[r'positionSeconds']}'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
        watched: mapValueOfType<bool>(json, r'watched')!,
        updatedAt: mapDateTime(json, r'updatedAt', r''),
      );
    }
    return null;
  }

  static List<PlayState> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlayState>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlayState.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PlayState> mapFromJson(dynamic json) {
    final map = <String, PlayState>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PlayState.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PlayState-objects as value to a dart map
  static Map<String, List<PlayState>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PlayState>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PlayState.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'positionSeconds',
    'watched',
  };
}

