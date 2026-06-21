//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TranscodeSession {
  /// Returns a new [TranscodeSession] instance.
  TranscodeSession({
    required this.id,
    required this.itemId,
    required this.encoder,
    required this.method,
    required this.state,
    required this.startAt,
    required this.startedAt,
    required this.playlistUrl,
    this.error,
    required this.progress,
  });

  String id;

  String itemId;

  String encoder;

  /// Whether this session copies codecs (remux) or re-encodes (transcode).
  TranscodeSessionMethodEnum method;

  TranscodeSessionStateEnum state;

  double startAt;

  DateTime startedAt;

  /// Relative URL of the HLS media playlist for this session.
  String playlistUrl;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? error;

  TranscodeProgress progress;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TranscodeSession &&
    other.id == id &&
    other.itemId == itemId &&
    other.encoder == encoder &&
    other.method == method &&
    other.state == state &&
    other.startAt == startAt &&
    other.startedAt == startedAt &&
    other.playlistUrl == playlistUrl &&
    other.error == error &&
    other.progress == progress;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (itemId.hashCode) +
    (encoder.hashCode) +
    (method.hashCode) +
    (state.hashCode) +
    (startAt.hashCode) +
    (startedAt.hashCode) +
    (playlistUrl.hashCode) +
    (error == null ? 0 : error!.hashCode) +
    (progress.hashCode);

  @override
  String toString() => 'TranscodeSession[id=$id, itemId=$itemId, encoder=$encoder, method=$method, state=$state, startAt=$startAt, startedAt=$startedAt, playlistUrl=$playlistUrl, error=$error, progress=$progress]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'itemId'] = this.itemId;
      json[r'encoder'] = this.encoder;
      json[r'method'] = this.method;
      json[r'state'] = this.state;
      json[r'startAt'] = this.startAt;
      json[r'startedAt'] = this.startedAt.toUtc().toIso8601String();
      json[r'playlistUrl'] = this.playlistUrl;
    if (this.error != null) {
      json[r'error'] = this.error;
    } else {
      json[r'error'] = null;
    }
      json[r'progress'] = this.progress;
    return json;
  }

  /// Returns a new [TranscodeSession] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TranscodeSession? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "TranscodeSession[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "TranscodeSession[id]" has a null value in JSON.');
        assert(json.containsKey(r'itemId'), 'Required key "TranscodeSession[itemId]" is missing from JSON.');
        assert(json[r'itemId'] != null, 'Required key "TranscodeSession[itemId]" has a null value in JSON.');
        assert(json.containsKey(r'encoder'), 'Required key "TranscodeSession[encoder]" is missing from JSON.');
        assert(json[r'encoder'] != null, 'Required key "TranscodeSession[encoder]" has a null value in JSON.');
        assert(json.containsKey(r'method'), 'Required key "TranscodeSession[method]" is missing from JSON.');
        assert(json[r'method'] != null, 'Required key "TranscodeSession[method]" has a null value in JSON.');
        assert(json.containsKey(r'state'), 'Required key "TranscodeSession[state]" is missing from JSON.');
        assert(json[r'state'] != null, 'Required key "TranscodeSession[state]" has a null value in JSON.');
        assert(json.containsKey(r'startAt'), 'Required key "TranscodeSession[startAt]" is missing from JSON.');
        assert(json[r'startAt'] != null, 'Required key "TranscodeSession[startAt]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'), 'Required key "TranscodeSession[startedAt]" is missing from JSON.');
        assert(json[r'startedAt'] != null, 'Required key "TranscodeSession[startedAt]" has a null value in JSON.');
        assert(json.containsKey(r'playlistUrl'), 'Required key "TranscodeSession[playlistUrl]" is missing from JSON.');
        assert(json[r'playlistUrl'] != null, 'Required key "TranscodeSession[playlistUrl]" has a null value in JSON.');
        assert(json.containsKey(r'progress'), 'Required key "TranscodeSession[progress]" is missing from JSON.');
        assert(json[r'progress'] != null, 'Required key "TranscodeSession[progress]" has a null value in JSON.');
        return true;
      }());

      return TranscodeSession(
        id: mapValueOfType<String>(json, r'id')!,
        itemId: mapValueOfType<String>(json, r'itemId')!,
        encoder: mapValueOfType<String>(json, r'encoder')!,
        method: TranscodeSessionMethodEnum.fromJson(json[r'method'])!,
        state: TranscodeSessionStateEnum.fromJson(json[r'state'])!,
        startAt: mapValueOfType<double>(json, r'startAt')!,
        startedAt: mapDateTime(json, r'startedAt', r'')!,
        playlistUrl: mapValueOfType<String>(json, r'playlistUrl')!,
        error: mapValueOfType<String>(json, r'error'),
        progress: TranscodeProgress.fromJson(json[r'progress'])!,
      );
    }
    return null;
  }

  static List<TranscodeSession> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeSession>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeSession.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TranscodeSession> mapFromJson(dynamic json) {
    final map = <String, TranscodeSession>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TranscodeSession.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TranscodeSession-objects as value to a dart map
  static Map<String, List<TranscodeSession>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TranscodeSession>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TranscodeSession.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'itemId',
    'encoder',
    'method',
    'state',
    'startAt',
    'startedAt',
    'playlistUrl',
    'progress',
  };
}

/// Whether this session copies codecs (remux) or re-encodes (transcode).
class TranscodeSessionMethodEnum {
  /// Instantiate a new enum with the provided [value].
  const TranscodeSessionMethodEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const remux = TranscodeSessionMethodEnum._(r'remux');
  static const transcode = TranscodeSessionMethodEnum._(r'transcode');

  /// List of all possible values in this [enum][TranscodeSessionMethodEnum].
  static const values = <TranscodeSessionMethodEnum>[
    remux,
    transcode,
  ];

  static TranscodeSessionMethodEnum? fromJson(dynamic value) => TranscodeSessionMethodEnumTypeTransformer().decode(value);

  static List<TranscodeSessionMethodEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeSessionMethodEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeSessionMethodEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [TranscodeSessionMethodEnum] to String,
/// and [decode] dynamic data back to [TranscodeSessionMethodEnum].
class TranscodeSessionMethodEnumTypeTransformer {
  factory TranscodeSessionMethodEnumTypeTransformer() => _instance ??= const TranscodeSessionMethodEnumTypeTransformer._();

  const TranscodeSessionMethodEnumTypeTransformer._();

  String encode(TranscodeSessionMethodEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a TranscodeSessionMethodEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  TranscodeSessionMethodEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'remux': return TranscodeSessionMethodEnum.remux;
        case r'transcode': return TranscodeSessionMethodEnum.transcode;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [TranscodeSessionMethodEnumTypeTransformer] instance.
  static TranscodeSessionMethodEnumTypeTransformer? _instance;
}



class TranscodeSessionStateEnum {
  /// Instantiate a new enum with the provided [value].
  const TranscodeSessionStateEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const starting = TranscodeSessionStateEnum._(r'starting');
  static const running = TranscodeSessionStateEnum._(r'running');
  static const complete = TranscodeSessionStateEnum._(r'complete');
  static const failed = TranscodeSessionStateEnum._(r'failed');
  static const stopped = TranscodeSessionStateEnum._(r'stopped');

  /// List of all possible values in this [enum][TranscodeSessionStateEnum].
  static const values = <TranscodeSessionStateEnum>[
    starting,
    running,
    complete,
    failed,
    stopped,
  ];

  static TranscodeSessionStateEnum? fromJson(dynamic value) => TranscodeSessionStateEnumTypeTransformer().decode(value);

  static List<TranscodeSessionStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeSessionStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeSessionStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [TranscodeSessionStateEnum] to String,
/// and [decode] dynamic data back to [TranscodeSessionStateEnum].
class TranscodeSessionStateEnumTypeTransformer {
  factory TranscodeSessionStateEnumTypeTransformer() => _instance ??= const TranscodeSessionStateEnumTypeTransformer._();

  const TranscodeSessionStateEnumTypeTransformer._();

  String encode(TranscodeSessionStateEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a TranscodeSessionStateEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  TranscodeSessionStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'starting': return TranscodeSessionStateEnum.starting;
        case r'running': return TranscodeSessionStateEnum.running;
        case r'complete': return TranscodeSessionStateEnum.complete;
        case r'failed': return TranscodeSessionStateEnum.failed;
        case r'stopped': return TranscodeSessionStateEnum.stopped;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [TranscodeSessionStateEnumTypeTransformer] instance.
  static TranscodeSessionStateEnumTypeTransformer? _instance;
}


