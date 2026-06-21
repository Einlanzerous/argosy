//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PingResponse {
  /// Returns a new [PingResponse] instance.
  PingResponse({
    required this.service,
    required this.status,
    required this.version,
  });

  String service;

  String status;

  String version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PingResponse &&
    other.service == service &&
    other.status == status &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (service.hashCode) +
    (status.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'PingResponse[service=$service, status=$status, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'service'] = this.service;
      json[r'status'] = this.status;
      json[r'version'] = this.version;
    return json;
  }

  /// Returns a new [PingResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PingResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'service'), 'Required key "PingResponse[service]" is missing from JSON.');
        assert(json[r'service'] != null, 'Required key "PingResponse[service]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "PingResponse[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "PingResponse[status]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "PingResponse[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "PingResponse[version]" has a null value in JSON.');
        return true;
      }());

      return PingResponse(
        service: mapValueOfType<String>(json, r'service')!,
        status: mapValueOfType<String>(json, r'status')!,
        version: mapValueOfType<String>(json, r'version')!,
      );
    }
    return null;
  }

  static List<PingResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PingResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PingResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PingResponse> mapFromJson(dynamic json) {
    final map = <String, PingResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PingResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PingResponse-objects as value to a dart map
  static Map<String, List<PingResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PingResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PingResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'service',
    'status',
    'version',
  };
}

