//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TranscodeCacheStats {
  /// Returns a new [TranscodeCacheStats] instance.
  TranscodeCacheStats({
    required this.totalBytes,
    required this.budgetBytes,
    required this.sessionDirs,
    required this.liveDirs,
  });

  int totalBytes;

  int budgetBytes;

  int sessionDirs;

  int liveDirs;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TranscodeCacheStats &&
    other.totalBytes == totalBytes &&
    other.budgetBytes == budgetBytes &&
    other.sessionDirs == sessionDirs &&
    other.liveDirs == liveDirs;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (totalBytes.hashCode) +
    (budgetBytes.hashCode) +
    (sessionDirs.hashCode) +
    (liveDirs.hashCode);

  @override
  String toString() => 'TranscodeCacheStats[totalBytes=$totalBytes, budgetBytes=$budgetBytes, sessionDirs=$sessionDirs, liveDirs=$liveDirs]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'totalBytes'] = this.totalBytes;
      json[r'budgetBytes'] = this.budgetBytes;
      json[r'sessionDirs'] = this.sessionDirs;
      json[r'liveDirs'] = this.liveDirs;
    return json;
  }

  /// Returns a new [TranscodeCacheStats] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TranscodeCacheStats? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'totalBytes'), 'Required key "TranscodeCacheStats[totalBytes]" is missing from JSON.');
        assert(json[r'totalBytes'] != null, 'Required key "TranscodeCacheStats[totalBytes]" has a null value in JSON.');
        assert(json.containsKey(r'budgetBytes'), 'Required key "TranscodeCacheStats[budgetBytes]" is missing from JSON.');
        assert(json[r'budgetBytes'] != null, 'Required key "TranscodeCacheStats[budgetBytes]" has a null value in JSON.');
        assert(json.containsKey(r'sessionDirs'), 'Required key "TranscodeCacheStats[sessionDirs]" is missing from JSON.');
        assert(json[r'sessionDirs'] != null, 'Required key "TranscodeCacheStats[sessionDirs]" has a null value in JSON.');
        assert(json.containsKey(r'liveDirs'), 'Required key "TranscodeCacheStats[liveDirs]" is missing from JSON.');
        assert(json[r'liveDirs'] != null, 'Required key "TranscodeCacheStats[liveDirs]" has a null value in JSON.');
        return true;
      }());

      return TranscodeCacheStats(
        totalBytes: mapValueOfType<int>(json, r'totalBytes')!,
        budgetBytes: mapValueOfType<int>(json, r'budgetBytes')!,
        sessionDirs: mapValueOfType<int>(json, r'sessionDirs')!,
        liveDirs: mapValueOfType<int>(json, r'liveDirs')!,
      );
    }
    return null;
  }

  static List<TranscodeCacheStats> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeCacheStats>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeCacheStats.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TranscodeCacheStats> mapFromJson(dynamic json) {
    final map = <String, TranscodeCacheStats>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TranscodeCacheStats.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TranscodeCacheStats-objects as value to a dart map
  static Map<String, List<TranscodeCacheStats>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TranscodeCacheStats>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TranscodeCacheStats.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'totalBytes',
    'budgetBytes',
    'sessionDirs',
    'liveDirs',
  };
}

