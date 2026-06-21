//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TranscodeProgress {
  /// Returns a new [TranscodeProgress] instance.
  TranscodeProgress({
    required this.outTimeMs,
    required this.speed,
    required this.fps,
  });

  /// Encoded timeline position in milliseconds.
  int outTimeMs;

  /// Encode speed as a multiple of realtime (2.5 == 2.5x).
  double speed;

  double fps;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TranscodeProgress &&
    other.outTimeMs == outTimeMs &&
    other.speed == speed &&
    other.fps == fps;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (outTimeMs.hashCode) +
    (speed.hashCode) +
    (fps.hashCode);

  @override
  String toString() => 'TranscodeProgress[outTimeMs=$outTimeMs, speed=$speed, fps=$fps]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'outTimeMs'] = this.outTimeMs;
      json[r'speed'] = this.speed;
      json[r'fps'] = this.fps;
    return json;
  }

  /// Returns a new [TranscodeProgress] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TranscodeProgress? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'outTimeMs'), 'Required key "TranscodeProgress[outTimeMs]" is missing from JSON.');
        assert(json[r'outTimeMs'] != null, 'Required key "TranscodeProgress[outTimeMs]" has a null value in JSON.');
        assert(json.containsKey(r'speed'), 'Required key "TranscodeProgress[speed]" is missing from JSON.');
        assert(json[r'speed'] != null, 'Required key "TranscodeProgress[speed]" has a null value in JSON.');
        assert(json.containsKey(r'fps'), 'Required key "TranscodeProgress[fps]" is missing from JSON.');
        assert(json[r'fps'] != null, 'Required key "TranscodeProgress[fps]" has a null value in JSON.');
        return true;
      }());

      return TranscodeProgress(
        outTimeMs: mapValueOfType<int>(json, r'outTimeMs')!,
        speed: mapValueOfType<double>(json, r'speed')!,
        fps: mapValueOfType<double>(json, r'fps')!,
      );
    }
    return null;
  }

  static List<TranscodeProgress> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeProgress>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeProgress.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TranscodeProgress> mapFromJson(dynamic json) {
    final map = <String, TranscodeProgress>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TranscodeProgress.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TranscodeProgress-objects as value to a dart map
  static Map<String, List<TranscodeProgress>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TranscodeProgress>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TranscodeProgress.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'outTimeMs',
    'speed',
    'fps',
  };
}

