//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class LinkStartResponse {
  /// Returns a new [LinkStartResponse] instance.
  LinkStartResponse({
    required this.code,
    required this.expiresAt,
  });

  /// Short, unambiguous pairing code the TV displays.
  String code;

  DateTime expiresAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LinkStartResponse &&
    other.code == code &&
    other.expiresAt == expiresAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (code.hashCode) +
    (expiresAt.hashCode);

  @override
  String toString() => 'LinkStartResponse[code=$code, expiresAt=$expiresAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'code'] = this.code;
      json[r'expiresAt'] = this.expiresAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [LinkStartResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static LinkStartResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'), 'Required key "LinkStartResponse[code]" is missing from JSON.');
        assert(json[r'code'] != null, 'Required key "LinkStartResponse[code]" has a null value in JSON.');
        assert(json.containsKey(r'expiresAt'), 'Required key "LinkStartResponse[expiresAt]" is missing from JSON.');
        assert(json[r'expiresAt'] != null, 'Required key "LinkStartResponse[expiresAt]" has a null value in JSON.');
        return true;
      }());

      return LinkStartResponse(
        code: mapValueOfType<String>(json, r'code')!,
        expiresAt: mapDateTime(json, r'expiresAt', r'')!,
      );
    }
    return null;
  }

  static List<LinkStartResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LinkStartResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LinkStartResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, LinkStartResponse> mapFromJson(dynamic json) {
    final map = <String, LinkStartResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = LinkStartResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of LinkStartResponse-objects as value to a dart map
  static Map<String, List<LinkStartResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<LinkStartResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = LinkStartResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
    'expiresAt',
  };
}

