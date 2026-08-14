//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class StowJob {
  /// Returns a new [StowJob] instance.
  StowJob({
    this.id,
    required this.itemId,
    required this.method,
    required this.state,
    this.downloadUrl,
    this.bytes,
    this.durationSeconds,
    this.progressSeconds,
    this.reason,
    this.error,
    this.createdAt,
    this.readyAt,
  });

  /// Job id, for polling and deletion. Absent for passthrough.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? id;

  String itemId;

  /// Whether the original file is handed over as-is (passthrough) or re-encoded into a single MP4 (package). 
  StowJobMethodEnum method;

  /// Passthrough is always `ready`. A package is `pending` while queued behind the encode concurrency limit, then `packaging`, then `ready` or `failed`. 
  StowJobStateEnum state;

  /// Relative URL to download the file from. Present once state is `ready`; the stream endpoint for a passthrough, the job's file endpoint for a package. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? downloadUrl;

  /// Size of the download in bytes — the source file for a passthrough, the packaged MP4 for a package (known only once ready). 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? bytes;

  /// Source duration, so a client can render packaging progress as a percentage.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? durationSeconds;

  /// How far the encode has reached along the source timeline.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? progressSeconds;

  /// Human-readable explanation of why this method was chosen, for the UI and the logs.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? reason;

  /// Failure detail when state is `failed`.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? error;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? createdAt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? readyAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is StowJob &&
    other.id == id &&
    other.itemId == itemId &&
    other.method == method &&
    other.state == state &&
    other.downloadUrl == downloadUrl &&
    other.bytes == bytes &&
    other.durationSeconds == durationSeconds &&
    other.progressSeconds == progressSeconds &&
    other.reason == reason &&
    other.error == error &&
    other.createdAt == createdAt &&
    other.readyAt == readyAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (itemId.hashCode) +
    (method.hashCode) +
    (state.hashCode) +
    (downloadUrl == null ? 0 : downloadUrl!.hashCode) +
    (bytes == null ? 0 : bytes!.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (progressSeconds == null ? 0 : progressSeconds!.hashCode) +
    (reason == null ? 0 : reason!.hashCode) +
    (error == null ? 0 : error!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode) +
    (readyAt == null ? 0 : readyAt!.hashCode);

  @override
  String toString() => 'StowJob[id=$id, itemId=$itemId, method=$method, state=$state, downloadUrl=$downloadUrl, bytes=$bytes, durationSeconds=$durationSeconds, progressSeconds=$progressSeconds, reason=$reason, error=$error, createdAt=$createdAt, readyAt=$readyAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
      json[r'itemId'] = this.itemId;
      json[r'method'] = this.method;
      json[r'state'] = this.state;
    if (this.downloadUrl != null) {
      json[r'downloadUrl'] = this.downloadUrl;
    } else {
      json[r'downloadUrl'] = null;
    }
    if (this.bytes != null) {
      json[r'bytes'] = this.bytes;
    } else {
      json[r'bytes'] = null;
    }
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
    if (this.progressSeconds != null) {
      json[r'progressSeconds'] = this.progressSeconds;
    } else {
      json[r'progressSeconds'] = null;
    }
    if (this.reason != null) {
      json[r'reason'] = this.reason;
    } else {
      json[r'reason'] = null;
    }
    if (this.error != null) {
      json[r'error'] = this.error;
    } else {
      json[r'error'] = null;
    }
    if (this.createdAt != null) {
      json[r'createdAt'] = this.createdAt!.toUtc().toIso8601String();
    } else {
      json[r'createdAt'] = null;
    }
    if (this.readyAt != null) {
      json[r'readyAt'] = this.readyAt!.toUtc().toIso8601String();
    } else {
      json[r'readyAt'] = null;
    }
    return json;
  }

  /// Returns a new [StowJob] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static StowJob? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'itemId'), 'Required key "StowJob[itemId]" is missing from JSON.');
        assert(json[r'itemId'] != null, 'Required key "StowJob[itemId]" has a null value in JSON.');
        assert(json.containsKey(r'method'), 'Required key "StowJob[method]" is missing from JSON.');
        assert(json[r'method'] != null, 'Required key "StowJob[method]" has a null value in JSON.');
        assert(json.containsKey(r'state'), 'Required key "StowJob[state]" is missing from JSON.');
        assert(json[r'state'] != null, 'Required key "StowJob[state]" has a null value in JSON.');
        return true;
      }());

      return StowJob(
        id: mapValueOfType<String>(json, r'id'),
        itemId: mapValueOfType<String>(json, r'itemId')!,
        method: StowJobMethodEnum.fromJson(json[r'method'])!,
        state: StowJobStateEnum.fromJson(json[r'state'])!,
        downloadUrl: mapValueOfType<String>(json, r'downloadUrl'),
        bytes: mapValueOfType<int>(json, r'bytes'),
        durationSeconds: mapValueOfType<double>(json, r'durationSeconds'),
        progressSeconds: mapValueOfType<double>(json, r'progressSeconds'),
        reason: mapValueOfType<String>(json, r'reason'),
        error: mapValueOfType<String>(json, r'error'),
        createdAt: mapDateTime(json, r'createdAt', r''),
        readyAt: mapDateTime(json, r'readyAt', r''),
      );
    }
    return null;
  }

  static List<StowJob> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StowJob>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StowJob.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, StowJob> mapFromJson(dynamic json) {
    final map = <String, StowJob>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = StowJob.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of StowJob-objects as value to a dart map
  static Map<String, List<StowJob>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<StowJob>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = StowJob.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'itemId',
    'method',
    'state',
  };
}

/// Whether the original file is handed over as-is (passthrough) or re-encoded into a single MP4 (package). 
class StowJobMethodEnum {
  /// Instantiate a new enum with the provided [value].
  const StowJobMethodEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const passthrough = StowJobMethodEnum._(r'passthrough');
  static const package = StowJobMethodEnum._(r'package');

  /// List of all possible values in this [enum][StowJobMethodEnum].
  static const values = <StowJobMethodEnum>[
    passthrough,
    package,
  ];

  static StowJobMethodEnum? fromJson(dynamic value) => StowJobMethodEnumTypeTransformer().decode(value);

  static List<StowJobMethodEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StowJobMethodEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StowJobMethodEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [StowJobMethodEnum] to String,
/// and [decode] dynamic data back to [StowJobMethodEnum].
class StowJobMethodEnumTypeTransformer {
  factory StowJobMethodEnumTypeTransformer() => _instance ??= const StowJobMethodEnumTypeTransformer._();

  const StowJobMethodEnumTypeTransformer._();

  String encode(StowJobMethodEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a StowJobMethodEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  StowJobMethodEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'passthrough': return StowJobMethodEnum.passthrough;
        case r'package': return StowJobMethodEnum.package;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [StowJobMethodEnumTypeTransformer] instance.
  static StowJobMethodEnumTypeTransformer? _instance;
}


/// Passthrough is always `ready`. A package is `pending` while queued behind the encode concurrency limit, then `packaging`, then `ready` or `failed`. 
class StowJobStateEnum {
  /// Instantiate a new enum with the provided [value].
  const StowJobStateEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const pending = StowJobStateEnum._(r'pending');
  static const packaging = StowJobStateEnum._(r'packaging');
  static const ready = StowJobStateEnum._(r'ready');
  static const failed = StowJobStateEnum._(r'failed');

  /// List of all possible values in this [enum][StowJobStateEnum].
  static const values = <StowJobStateEnum>[
    pending,
    packaging,
    ready,
    failed,
  ];

  static StowJobStateEnum? fromJson(dynamic value) => StowJobStateEnumTypeTransformer().decode(value);

  static List<StowJobStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StowJobStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StowJobStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [StowJobStateEnum] to String,
/// and [decode] dynamic data back to [StowJobStateEnum].
class StowJobStateEnumTypeTransformer {
  factory StowJobStateEnumTypeTransformer() => _instance ??= const StowJobStateEnumTypeTransformer._();

  const StowJobStateEnumTypeTransformer._();

  String encode(StowJobStateEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a StowJobStateEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  StowJobStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'pending': return StowJobStateEnum.pending;
        case r'packaging': return StowJobStateEnum.packaging;
        case r'ready': return StowJobStateEnum.ready;
        case r'failed': return StowJobStateEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [StowJobStateEnumTypeTransformer] instance.
  static StowJobStateEnumTypeTransformer? _instance;
}


