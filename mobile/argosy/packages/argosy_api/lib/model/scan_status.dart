//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ScanStatus {
  /// Returns a new [ScanStatus] instance.
  ScanStatus({
    required this.running,
    this.startedAt,
    this.finishedAt,
    this.libraries = const [],
  });

  bool running;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? startedAt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? finishedAt;

  List<ScanLibraryResult> libraries;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ScanStatus &&
    other.running == running &&
    other.startedAt == startedAt &&
    other.finishedAt == finishedAt &&
    _deepEquality.equals(other.libraries, libraries);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (running.hashCode) +
    (startedAt == null ? 0 : startedAt!.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode) +
    (libraries.hashCode);

  @override
  String toString() => 'ScanStatus[running=$running, startedAt=$startedAt, finishedAt=$finishedAt, libraries=$libraries]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'running'] = this.running;
    if (this.startedAt != null) {
      json[r'startedAt'] = this.startedAt!.toUtc().toIso8601String();
    } else {
      json[r'startedAt'] = null;
    }
    if (this.finishedAt != null) {
      json[r'finishedAt'] = this.finishedAt!.toUtc().toIso8601String();
    } else {
      json[r'finishedAt'] = null;
    }
      json[r'libraries'] = this.libraries;
    return json;
  }

  /// Returns a new [ScanStatus] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ScanStatus? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'running'), 'Required key "ScanStatus[running]" is missing from JSON.');
        assert(json[r'running'] != null, 'Required key "ScanStatus[running]" has a null value in JSON.');
        assert(json.containsKey(r'libraries'), 'Required key "ScanStatus[libraries]" is missing from JSON.');
        assert(json[r'libraries'] != null, 'Required key "ScanStatus[libraries]" has a null value in JSON.');
        return true;
      }());

      return ScanStatus(
        running: mapValueOfType<bool>(json, r'running')!,
        startedAt: mapDateTime(json, r'startedAt', r''),
        finishedAt: mapDateTime(json, r'finishedAt', r''),
        libraries: ScanLibraryResult.listFromJson(json[r'libraries']),
      );
    }
    return null;
  }

  static List<ScanStatus> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ScanStatus>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ScanStatus.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ScanStatus> mapFromJson(dynamic json) {
    final map = <String, ScanStatus>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ScanStatus.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ScanStatus-objects as value to a dart map
  static Map<String, List<ScanStatus>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ScanStatus>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ScanStatus.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'running',
    'libraries',
  };
}

