//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PlaybackInfo {
  /// Returns a new [PlaybackInfo] instance.
  PlaybackInfo({
    required this.directPlay,
    required this.method,
    required this.container,
    this.videoCodec,
    this.audioCodec,
    this.reason,
  });

  bool directPlay;

  /// Cheapest playable path — serve as-is, repackage (copy codecs), or re-encode.
  PlaybackInfoMethodEnum method;

  String container;

  String? videoCodec;

  String? audioCodec;

  String? reason;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PlaybackInfo &&
    other.directPlay == directPlay &&
    other.method == method &&
    other.container == container &&
    other.videoCodec == videoCodec &&
    other.audioCodec == audioCodec &&
    other.reason == reason;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (directPlay.hashCode) +
    (method.hashCode) +
    (container.hashCode) +
    (videoCodec == null ? 0 : videoCodec!.hashCode) +
    (audioCodec == null ? 0 : audioCodec!.hashCode) +
    (reason == null ? 0 : reason!.hashCode);

  @override
  String toString() => 'PlaybackInfo[directPlay=$directPlay, method=$method, container=$container, videoCodec=$videoCodec, audioCodec=$audioCodec, reason=$reason]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'directPlay'] = this.directPlay;
      json[r'method'] = this.method;
      json[r'container'] = this.container;
    if (this.videoCodec != null) {
      json[r'videoCodec'] = this.videoCodec;
    } else {
      json[r'videoCodec'] = null;
    }
    if (this.audioCodec != null) {
      json[r'audioCodec'] = this.audioCodec;
    } else {
      json[r'audioCodec'] = null;
    }
    if (this.reason != null) {
      json[r'reason'] = this.reason;
    } else {
      json[r'reason'] = null;
    }
    return json;
  }

  /// Returns a new [PlaybackInfo] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PlaybackInfo? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'directPlay'), 'Required key "PlaybackInfo[directPlay]" is missing from JSON.');
        assert(json[r'directPlay'] != null, 'Required key "PlaybackInfo[directPlay]" has a null value in JSON.');
        assert(json.containsKey(r'method'), 'Required key "PlaybackInfo[method]" is missing from JSON.');
        assert(json[r'method'] != null, 'Required key "PlaybackInfo[method]" has a null value in JSON.');
        assert(json.containsKey(r'container'), 'Required key "PlaybackInfo[container]" is missing from JSON.');
        assert(json[r'container'] != null, 'Required key "PlaybackInfo[container]" has a null value in JSON.');
        return true;
      }());

      return PlaybackInfo(
        directPlay: mapValueOfType<bool>(json, r'directPlay')!,
        method: PlaybackInfoMethodEnum.fromJson(json[r'method'])!,
        container: mapValueOfType<String>(json, r'container')!,
        videoCodec: mapValueOfType<String>(json, r'videoCodec'),
        audioCodec: mapValueOfType<String>(json, r'audioCodec'),
        reason: mapValueOfType<String>(json, r'reason'),
      );
    }
    return null;
  }

  static List<PlaybackInfo> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackInfo>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackInfo.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PlaybackInfo> mapFromJson(dynamic json) {
    final map = <String, PlaybackInfo>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PlaybackInfo.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PlaybackInfo-objects as value to a dart map
  static Map<String, List<PlaybackInfo>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PlaybackInfo>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PlaybackInfo.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'directPlay',
    'method',
    'container',
  };
}

/// Cheapest playable path — serve as-is, repackage (copy codecs), or re-encode.
class PlaybackInfoMethodEnum {
  /// Instantiate a new enum with the provided [value].
  const PlaybackInfoMethodEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const direct = PlaybackInfoMethodEnum._(r'direct');
  static const remux = PlaybackInfoMethodEnum._(r'remux');
  static const transcode = PlaybackInfoMethodEnum._(r'transcode');

  /// List of all possible values in this [enum][PlaybackInfoMethodEnum].
  static const values = <PlaybackInfoMethodEnum>[
    direct,
    remux,
    transcode,
  ];

  static PlaybackInfoMethodEnum? fromJson(dynamic value) => PlaybackInfoMethodEnumTypeTransformer().decode(value);

  static List<PlaybackInfoMethodEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackInfoMethodEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackInfoMethodEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PlaybackInfoMethodEnum] to String,
/// and [decode] dynamic data back to [PlaybackInfoMethodEnum].
class PlaybackInfoMethodEnumTypeTransformer {
  factory PlaybackInfoMethodEnumTypeTransformer() => _instance ??= const PlaybackInfoMethodEnumTypeTransformer._();

  const PlaybackInfoMethodEnumTypeTransformer._();

  String encode(PlaybackInfoMethodEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a PlaybackInfoMethodEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PlaybackInfoMethodEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'direct': return PlaybackInfoMethodEnum.direct;
        case r'remux': return PlaybackInfoMethodEnum.remux;
        case r'transcode': return PlaybackInfoMethodEnum.transcode;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [PlaybackInfoMethodEnumTypeTransformer] instance.
  static PlaybackInfoMethodEnumTypeTransformer? _instance;
}


