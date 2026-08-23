//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class HealthResponse {
  /// Returns a new [HealthResponse] instance.
  HealthResponse({
    required this.status,
    required this.version,
    required this.sha,
  });

  HealthResponseStatusEnum status;

  /// Bare semver, or the literal \"dev\" for a build no release cut. Never carries a \"v\" prefix: it is compared with strict equality against the image's org.opencontainers.image.version label, which is stamped bare, and a prefix would never match.
  String version;

  /// The full 40-character commit, or null when the build supplied none. Never abbreviated — the cross-service comparison is an equality test, not a prefix match.
  String? sha;

  @override
  bool operator ==(Object other) => identical(this, other) || other is HealthResponse &&
    other.status == status &&
    other.version == version &&
    other.sha == sha;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status.hashCode) +
    (version.hashCode) +
    (sha == null ? 0 : sha!.hashCode);

  @override
  String toString() => 'HealthResponse[status=$status, version=$version, sha=$sha]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'status'] = this.status;
      json[r'version'] = this.version;
    if (this.sha != null) {
      json[r'sha'] = this.sha;
    } else {
      json[r'sha'] = null;
    }
    return json;
  }

  /// Returns a new [HealthResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static HealthResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'), 'Required key "HealthResponse[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "HealthResponse[status]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "HealthResponse[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "HealthResponse[version]" has a null value in JSON.');
        assert(json.containsKey(r'sha'), 'Required key "HealthResponse[sha]" is missing from JSON.');
        return true;
      }());

      return HealthResponse(
        status: HealthResponseStatusEnum.fromJson(json[r'status'])!,
        version: mapValueOfType<String>(json, r'version')!,
        sha: mapValueOfType<String>(json, r'sha'),
      );
    }
    return null;
  }

  static List<HealthResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <HealthResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, HealthResponse> mapFromJson(dynamic json) {
    final map = <String, HealthResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = HealthResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of HealthResponse-objects as value to a dart map
  static Map<String, List<HealthResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<HealthResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = HealthResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'status',
    'version',
    'sha',
  };
}


class HealthResponseStatusEnum {
  /// Instantiate a new enum with the provided [value].
  const HealthResponseStatusEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const ok = HealthResponseStatusEnum._(r'ok');
  static const degraded = HealthResponseStatusEnum._(r'degraded');

  /// List of all possible values in this [enum][HealthResponseStatusEnum].
  static const values = <HealthResponseStatusEnum>[
    ok,
    degraded,
  ];

  static HealthResponseStatusEnum? fromJson(dynamic value) => HealthResponseStatusEnumTypeTransformer().decode(value);

  static List<HealthResponseStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <HealthResponseStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthResponseStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [HealthResponseStatusEnum] to String,
/// and [decode] dynamic data back to [HealthResponseStatusEnum].
class HealthResponseStatusEnumTypeTransformer {
  factory HealthResponseStatusEnumTypeTransformer() => _instance ??= const HealthResponseStatusEnumTypeTransformer._();

  const HealthResponseStatusEnumTypeTransformer._();

  String encode(HealthResponseStatusEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a HealthResponseStatusEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  HealthResponseStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'ok': return HealthResponseStatusEnum.ok;
        case r'degraded': return HealthResponseStatusEnum.degraded;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [HealthResponseStatusEnumTypeTransformer] instance.
  static HealthResponseStatusEnumTypeTransformer? _instance;
}


