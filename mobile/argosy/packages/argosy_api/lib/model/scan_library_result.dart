//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ScanLibraryResult {
  /// Returns a new [ScanLibraryResult] instance.
  ScanLibraryResult({
    required this.libraryId,
    required this.name,
    required this.scanned,
    required this.errors,
    this.error,
  });

  String libraryId;

  String name;

  int scanned;

  int errors;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? error;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ScanLibraryResult &&
    other.libraryId == libraryId &&
    other.name == name &&
    other.scanned == scanned &&
    other.errors == errors &&
    other.error == error;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (libraryId.hashCode) +
    (name.hashCode) +
    (scanned.hashCode) +
    (errors.hashCode) +
    (error == null ? 0 : error!.hashCode);

  @override
  String toString() => 'ScanLibraryResult[libraryId=$libraryId, name=$name, scanned=$scanned, errors=$errors, error=$error]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'libraryId'] = this.libraryId;
      json[r'name'] = this.name;
      json[r'scanned'] = this.scanned;
      json[r'errors'] = this.errors;
    if (this.error != null) {
      json[r'error'] = this.error;
    } else {
      json[r'error'] = null;
    }
    return json;
  }

  /// Returns a new [ScanLibraryResult] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ScanLibraryResult? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'libraryId'), 'Required key "ScanLibraryResult[libraryId]" is missing from JSON.');
        assert(json[r'libraryId'] != null, 'Required key "ScanLibraryResult[libraryId]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "ScanLibraryResult[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ScanLibraryResult[name]" has a null value in JSON.');
        assert(json.containsKey(r'scanned'), 'Required key "ScanLibraryResult[scanned]" is missing from JSON.');
        assert(json[r'scanned'] != null, 'Required key "ScanLibraryResult[scanned]" has a null value in JSON.');
        assert(json.containsKey(r'errors'), 'Required key "ScanLibraryResult[errors]" is missing from JSON.');
        assert(json[r'errors'] != null, 'Required key "ScanLibraryResult[errors]" has a null value in JSON.');
        return true;
      }());

      return ScanLibraryResult(
        libraryId: mapValueOfType<String>(json, r'libraryId')!,
        name: mapValueOfType<String>(json, r'name')!,
        scanned: mapValueOfType<int>(json, r'scanned')!,
        errors: mapValueOfType<int>(json, r'errors')!,
        error: mapValueOfType<String>(json, r'error'),
      );
    }
    return null;
  }

  static List<ScanLibraryResult> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ScanLibraryResult>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ScanLibraryResult.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ScanLibraryResult> mapFromJson(dynamic json) {
    final map = <String, ScanLibraryResult>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ScanLibraryResult.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ScanLibraryResult-objects as value to a dart map
  static Map<String, List<ScanLibraryResult>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ScanLibraryResult>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ScanLibraryResult.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'libraryId',
    'name',
    'scanned',
    'errors',
  };
}

