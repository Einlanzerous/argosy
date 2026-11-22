//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SessionsSummary {
  /// Returns a new [SessionsSummary] instance.
  SessionsSummary({
    required this.watchingNow,
    required this.asOf,
  });

  /// Sessions in state `playing`, across all accounts.
  ///
  /// Minimum value: 0
  int watchingNow;

  /// When the count was read.
  DateTime asOf;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SessionsSummary &&
    other.watchingNow == watchingNow &&
    other.asOf == asOf;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (watchingNow.hashCode) +
    (asOf.hashCode);

  @override
  String toString() => 'SessionsSummary[watchingNow=$watchingNow, asOf=$asOf]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'watchingNow'] = this.watchingNow;
      json[r'asOf'] = this.asOf.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [SessionsSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SessionsSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'watchingNow'), 'Required key "SessionsSummary[watchingNow]" is missing from JSON.');
        assert(json[r'watchingNow'] != null, 'Required key "SessionsSummary[watchingNow]" has a null value in JSON.');
        assert(json.containsKey(r'asOf'), 'Required key "SessionsSummary[asOf]" is missing from JSON.');
        assert(json[r'asOf'] != null, 'Required key "SessionsSummary[asOf]" has a null value in JSON.');
        return true;
      }());

      return SessionsSummary(
        watchingNow: mapValueOfType<int>(json, r'watchingNow')!,
        asOf: mapDateTime(json, r'asOf', r'')!,
      );
    }
    return null;
  }

  static List<SessionsSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SessionsSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SessionsSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SessionsSummary> mapFromJson(dynamic json) {
    final map = <String, SessionsSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SessionsSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SessionsSummary-objects as value to a dart map
  static Map<String, List<SessionsSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SessionsSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SessionsSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'watchingNow',
    'asOf',
  };
}

