//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PlaybackEvent {
  /// Returns a new [PlaybackEvent] instance.
  PlaybackEvent({
    required this.kind,
    required this.positionSeconds,
    required this.durationMs,
    required this.cause,
    this.ended,
    this.recovered,
    this.sessionId,
    this.bufferedAheadSeconds,
    this.delivery,
  });

  PlaybackEventKindEnum kind;

  /// Absolute playhead position when the stall began.
  num positionSeconds;

  /// How long the player was stalled; so far when ended is false.
  int durationMs;

  /// seek: within a few seconds of a user seek. resume: shortly after the app returned to the foreground or left PiP. play: mid-playback.
  PlaybackEventCauseEnum cause;

  /// False when the stall was cut short: the viewer left the player, or recovery restarted it. Absent means true.
  bool? ended;

  /// True when the stall ended because the player's recovery restarted the session (the stream died), not because it caught up. Implies ended is false.
  bool? recovered;

  /// Transcode session id, when there is one.
  String? sessionId;

  /// Seconds buffered ahead of the playhead when the stall began, if known.
  num? bufferedAheadSeconds;

  /// Delivery method, when the client knows it.
  PlaybackEventDeliveryEnum? delivery;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PlaybackEvent &&
    other.kind == kind &&
    other.positionSeconds == positionSeconds &&
    other.durationMs == durationMs &&
    other.cause == cause &&
    other.ended == ended &&
    other.recovered == recovered &&
    other.sessionId == sessionId &&
    other.bufferedAheadSeconds == bufferedAheadSeconds &&
    other.delivery == delivery;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (kind.hashCode) +
    (positionSeconds.hashCode) +
    (durationMs.hashCode) +
    (cause.hashCode) +
    (ended == null ? 0 : ended!.hashCode) +
    (recovered == null ? 0 : recovered!.hashCode) +
    (sessionId == null ? 0 : sessionId!.hashCode) +
    (bufferedAheadSeconds == null ? 0 : bufferedAheadSeconds!.hashCode) +
    (delivery == null ? 0 : delivery!.hashCode);

  @override
  String toString() => 'PlaybackEvent[kind=$kind, positionSeconds=$positionSeconds, durationMs=$durationMs, cause=$cause, ended=$ended, recovered=$recovered, sessionId=$sessionId, bufferedAheadSeconds=$bufferedAheadSeconds, delivery=$delivery]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'kind'] = this.kind;
      json[r'positionSeconds'] = this.positionSeconds;
      json[r'durationMs'] = this.durationMs;
      json[r'cause'] = this.cause;
    if (this.ended != null) {
      json[r'ended'] = this.ended;
    } else {
      json[r'ended'] = null;
    }
    if (this.recovered != null) {
      json[r'recovered'] = this.recovered;
    } else {
      json[r'recovered'] = null;
    }
    if (this.sessionId != null) {
      json[r'sessionId'] = this.sessionId;
    } else {
      json[r'sessionId'] = null;
    }
    if (this.bufferedAheadSeconds != null) {
      json[r'bufferedAheadSeconds'] = this.bufferedAheadSeconds;
    } else {
      json[r'bufferedAheadSeconds'] = null;
    }
    if (this.delivery != null) {
      json[r'delivery'] = this.delivery;
    } else {
      json[r'delivery'] = null;
    }
    return json;
  }

  /// Returns a new [PlaybackEvent] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PlaybackEvent? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'kind'), 'Required key "PlaybackEvent[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "PlaybackEvent[kind]" has a null value in JSON.');
        assert(json.containsKey(r'positionSeconds'), 'Required key "PlaybackEvent[positionSeconds]" is missing from JSON.');
        assert(json[r'positionSeconds'] != null, 'Required key "PlaybackEvent[positionSeconds]" has a null value in JSON.');
        assert(json.containsKey(r'durationMs'), 'Required key "PlaybackEvent[durationMs]" is missing from JSON.');
        assert(json[r'durationMs'] != null, 'Required key "PlaybackEvent[durationMs]" has a null value in JSON.');
        assert(json.containsKey(r'cause'), 'Required key "PlaybackEvent[cause]" is missing from JSON.');
        assert(json[r'cause'] != null, 'Required key "PlaybackEvent[cause]" has a null value in JSON.');
        return true;
      }());

      return PlaybackEvent(
        kind: PlaybackEventKindEnum.fromJson(json[r'kind'])!,
        positionSeconds: num.parse('${json[r'positionSeconds']}'),
        durationMs: mapValueOfType<int>(json, r'durationMs')!,
        cause: PlaybackEventCauseEnum.fromJson(json[r'cause'])!,
        ended: mapValueOfType<bool>(json, r'ended'),
        recovered: mapValueOfType<bool>(json, r'recovered'),
        sessionId: mapValueOfType<String>(json, r'sessionId'),
        bufferedAheadSeconds: json[r'bufferedAheadSeconds'] == null
            ? null
            : num.parse('${json[r'bufferedAheadSeconds']}'),
        delivery: PlaybackEventDeliveryEnum.fromJson(json[r'delivery']),
      );
    }
    return null;
  }

  static List<PlaybackEvent> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackEvent>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackEvent.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PlaybackEvent> mapFromJson(dynamic json) {
    final map = <String, PlaybackEvent>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PlaybackEvent.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PlaybackEvent-objects as value to a dart map
  static Map<String, List<PlaybackEvent>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PlaybackEvent>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PlaybackEvent.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'kind',
    'positionSeconds',
    'durationMs',
    'cause',
  };
}


class PlaybackEventKindEnum {
  /// Instantiate a new enum with the provided [value].
  const PlaybackEventKindEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const stall = PlaybackEventKindEnum._(r'stall');

  /// List of all possible values in this [enum][PlaybackEventKindEnum].
  static const values = <PlaybackEventKindEnum>[
    stall,
  ];

  static PlaybackEventKindEnum? fromJson(dynamic value) => PlaybackEventKindEnumTypeTransformer().decode(value);

  static List<PlaybackEventKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackEventKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackEventKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PlaybackEventKindEnum] to String,
/// and [decode] dynamic data back to [PlaybackEventKindEnum].
class PlaybackEventKindEnumTypeTransformer {
  factory PlaybackEventKindEnumTypeTransformer() => _instance ??= const PlaybackEventKindEnumTypeTransformer._();

  const PlaybackEventKindEnumTypeTransformer._();

  String encode(PlaybackEventKindEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a PlaybackEventKindEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PlaybackEventKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'stall': return PlaybackEventKindEnum.stall;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [PlaybackEventKindEnumTypeTransformer] instance.
  static PlaybackEventKindEnumTypeTransformer? _instance;
}


/// seek: within a few seconds of a user seek. resume: shortly after the app returned to the foreground or left PiP. play: mid-playback.
class PlaybackEventCauseEnum {
  /// Instantiate a new enum with the provided [value].
  const PlaybackEventCauseEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const seek = PlaybackEventCauseEnum._(r'seek');
  static const resume = PlaybackEventCauseEnum._(r'resume');
  static const play = PlaybackEventCauseEnum._(r'play');

  /// List of all possible values in this [enum][PlaybackEventCauseEnum].
  static const values = <PlaybackEventCauseEnum>[
    seek,
    resume,
    play,
  ];

  static PlaybackEventCauseEnum? fromJson(dynamic value) => PlaybackEventCauseEnumTypeTransformer().decode(value);

  static List<PlaybackEventCauseEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackEventCauseEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackEventCauseEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PlaybackEventCauseEnum] to String,
/// and [decode] dynamic data back to [PlaybackEventCauseEnum].
class PlaybackEventCauseEnumTypeTransformer {
  factory PlaybackEventCauseEnumTypeTransformer() => _instance ??= const PlaybackEventCauseEnumTypeTransformer._();

  const PlaybackEventCauseEnumTypeTransformer._();

  String encode(PlaybackEventCauseEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a PlaybackEventCauseEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PlaybackEventCauseEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'seek': return PlaybackEventCauseEnum.seek;
        case r'resume': return PlaybackEventCauseEnum.resume;
        case r'play': return PlaybackEventCauseEnum.play;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [PlaybackEventCauseEnumTypeTransformer] instance.
  static PlaybackEventCauseEnumTypeTransformer? _instance;
}


/// Delivery method, when the client knows it.
class PlaybackEventDeliveryEnum {
  /// Instantiate a new enum with the provided [value].
  const PlaybackEventDeliveryEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const remux = PlaybackEventDeliveryEnum._(r'remux');
  static const transcode = PlaybackEventDeliveryEnum._(r'transcode');
  static const direct = PlaybackEventDeliveryEnum._(r'direct');

  /// List of all possible values in this [enum][PlaybackEventDeliveryEnum].
  static const values = <PlaybackEventDeliveryEnum>[
    remux,
    transcode,
    direct,
  ];

  static PlaybackEventDeliveryEnum? fromJson(dynamic value) => PlaybackEventDeliveryEnumTypeTransformer().decode(value);

  static List<PlaybackEventDeliveryEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackEventDeliveryEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackEventDeliveryEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PlaybackEventDeliveryEnum] to String,
/// and [decode] dynamic data back to [PlaybackEventDeliveryEnum].
class PlaybackEventDeliveryEnumTypeTransformer {
  factory PlaybackEventDeliveryEnumTypeTransformer() => _instance ??= const PlaybackEventDeliveryEnumTypeTransformer._();

  const PlaybackEventDeliveryEnumTypeTransformer._();

  String encode(PlaybackEventDeliveryEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a PlaybackEventDeliveryEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PlaybackEventDeliveryEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'remux': return PlaybackEventDeliveryEnum.remux;
        case r'transcode': return PlaybackEventDeliveryEnum.transcode;
        case r'direct': return PlaybackEventDeliveryEnum.direct;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [PlaybackEventDeliveryEnumTypeTransformer] instance.
  static PlaybackEventDeliveryEnumTypeTransformer? _instance;
}


