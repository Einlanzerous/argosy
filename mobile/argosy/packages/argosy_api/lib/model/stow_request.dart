//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class StowRequest {
  /// Returns a new [StowRequest] instance.
  StowRequest({
    this.hevc,
    this.matroska,
  });

  /// Whether the client hardware-decodes HEVC (H.265). True lets an HEVC source be handed over untouched instead of re-encoded to H.264, which for a big library is the difference between an instant stow and a long encode. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? hevc;

  /// Whether the client's player handles the Matroska (.mkv) container. True on Android (ExoPlayer), false on iOS (AVPlayer), which is why this is asked rather than assumed — most of a typical library is mkv, and the answer decides whether that library packages or passes through. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? matroska;

  @override
  bool operator ==(Object other) => identical(this, other) || other is StowRequest &&
    other.hevc == hevc &&
    other.matroska == matroska;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (hevc == null ? 0 : hevc!.hashCode) +
    (matroska == null ? 0 : matroska!.hashCode);

  @override
  String toString() => 'StowRequest[hevc=$hevc, matroska=$matroska]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.hevc != null) {
      json[r'hevc'] = this.hevc;
    } else {
      json[r'hevc'] = null;
    }
    if (this.matroska != null) {
      json[r'matroska'] = this.matroska;
    } else {
      json[r'matroska'] = null;
    }
    return json;
  }

  /// Returns a new [StowRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static StowRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return StowRequest(
        hevc: mapValueOfType<bool>(json, r'hevc'),
        matroska: mapValueOfType<bool>(json, r'matroska'),
      );
    }
    return null;
  }

  static List<StowRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StowRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StowRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, StowRequest> mapFromJson(dynamic json) {
    final map = <String, StowRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = StowRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of StowRequest-objects as value to a dart map
  static Map<String, List<StowRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<StowRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = StowRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

