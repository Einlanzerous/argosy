//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevicePreferences {
  /// Returns a new [DevicePreferences] instance.
  DevicePreferences({
    this.subtitleLanguage,
    required this.subtitleEnabled,
    this.audioLanguage,
    this.captionScale,
    this.captionColor,
    this.captionBackground,
    this.seriesAutoAdvance,
  });

  /// Preferred subtitle language (ISO code); the player auto-selects a matching track.
  String? subtitleLanguage;

  /// Whether subtitles are on by default.
  bool subtitleEnabled;

  /// Preferred audio language (ISO code). Persisted; applied once audio-track selection ships.
  String? audioLanguage;

  /// Caption font scale (1.0 = default).
  num? captionScale;

  /// Caption text color (hex).
  String? captionColor;

  /// Caption background box style.
  DevicePreferencesCaptionBackgroundEnum? captionBackground;

  /// Whether finishing a series episode auto-plays the next one. Defaults to true (on) when unset.
  bool? seriesAutoAdvance;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevicePreferences &&
    other.subtitleLanguage == subtitleLanguage &&
    other.subtitleEnabled == subtitleEnabled &&
    other.audioLanguage == audioLanguage &&
    other.captionScale == captionScale &&
    other.captionColor == captionColor &&
    other.captionBackground == captionBackground &&
    other.seriesAutoAdvance == seriesAutoAdvance;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (subtitleLanguage == null ? 0 : subtitleLanguage!.hashCode) +
    (subtitleEnabled.hashCode) +
    (audioLanguage == null ? 0 : audioLanguage!.hashCode) +
    (captionScale == null ? 0 : captionScale!.hashCode) +
    (captionColor == null ? 0 : captionColor!.hashCode) +
    (captionBackground == null ? 0 : captionBackground!.hashCode) +
    (seriesAutoAdvance == null ? 0 : seriesAutoAdvance!.hashCode);

  @override
  String toString() => 'DevicePreferences[subtitleLanguage=$subtitleLanguage, subtitleEnabled=$subtitleEnabled, audioLanguage=$audioLanguage, captionScale=$captionScale, captionColor=$captionColor, captionBackground=$captionBackground, seriesAutoAdvance=$seriesAutoAdvance]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.subtitleLanguage != null) {
      json[r'subtitleLanguage'] = this.subtitleLanguage;
    } else {
      json[r'subtitleLanguage'] = null;
    }
      json[r'subtitleEnabled'] = this.subtitleEnabled;
    if (this.audioLanguage != null) {
      json[r'audioLanguage'] = this.audioLanguage;
    } else {
      json[r'audioLanguage'] = null;
    }
    if (this.captionScale != null) {
      json[r'captionScale'] = this.captionScale;
    } else {
      json[r'captionScale'] = null;
    }
    if (this.captionColor != null) {
      json[r'captionColor'] = this.captionColor;
    } else {
      json[r'captionColor'] = null;
    }
    if (this.captionBackground != null) {
      json[r'captionBackground'] = this.captionBackground;
    } else {
      json[r'captionBackground'] = null;
    }
    if (this.seriesAutoAdvance != null) {
      json[r'seriesAutoAdvance'] = this.seriesAutoAdvance;
    } else {
      json[r'seriesAutoAdvance'] = null;
    }
    return json;
  }

  /// Returns a new [DevicePreferences] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevicePreferences? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'subtitleEnabled'), 'Required key "DevicePreferences[subtitleEnabled]" is missing from JSON.');
        assert(json[r'subtitleEnabled'] != null, 'Required key "DevicePreferences[subtitleEnabled]" has a null value in JSON.');
        return true;
      }());

      return DevicePreferences(
        subtitleLanguage: mapValueOfType<String>(json, r'subtitleLanguage'),
        subtitleEnabled: mapValueOfType<bool>(json, r'subtitleEnabled')!,
        audioLanguage: mapValueOfType<String>(json, r'audioLanguage'),
        captionScale: json[r'captionScale'] == null
            ? null
            : num.parse('${json[r'captionScale']}'),
        captionColor: mapValueOfType<String>(json, r'captionColor'),
        captionBackground: DevicePreferencesCaptionBackgroundEnum.fromJson(json[r'captionBackground']),
        seriesAutoAdvance: mapValueOfType<bool>(json, r'seriesAutoAdvance'),
      );
    }
    return null;
  }

  static List<DevicePreferences> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevicePreferences>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevicePreferences.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevicePreferences> mapFromJson(dynamic json) {
    final map = <String, DevicePreferences>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevicePreferences.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevicePreferences-objects as value to a dart map
  static Map<String, List<DevicePreferences>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevicePreferences>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevicePreferences.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'subtitleEnabled',
  };
}

/// Caption background box style.
class DevicePreferencesCaptionBackgroundEnum {
  /// Instantiate a new enum with the provided [value].
  const DevicePreferencesCaptionBackgroundEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const translucent = DevicePreferencesCaptionBackgroundEnum._(r'translucent');
  static const solid = DevicePreferencesCaptionBackgroundEnum._(r'solid');
  static const none = DevicePreferencesCaptionBackgroundEnum._(r'none');

  /// List of all possible values in this [enum][DevicePreferencesCaptionBackgroundEnum].
  static const values = <DevicePreferencesCaptionBackgroundEnum>[
    translucent,
    solid,
    none,
  ];

  static DevicePreferencesCaptionBackgroundEnum? fromJson(dynamic value) => DevicePreferencesCaptionBackgroundEnumTypeTransformer().decode(value);

  static List<DevicePreferencesCaptionBackgroundEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevicePreferencesCaptionBackgroundEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevicePreferencesCaptionBackgroundEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DevicePreferencesCaptionBackgroundEnum] to String,
/// and [decode] dynamic data back to [DevicePreferencesCaptionBackgroundEnum].
class DevicePreferencesCaptionBackgroundEnumTypeTransformer {
  factory DevicePreferencesCaptionBackgroundEnumTypeTransformer() => _instance ??= const DevicePreferencesCaptionBackgroundEnumTypeTransformer._();

  const DevicePreferencesCaptionBackgroundEnumTypeTransformer._();

  String encode(DevicePreferencesCaptionBackgroundEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a DevicePreferencesCaptionBackgroundEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DevicePreferencesCaptionBackgroundEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'translucent': return DevicePreferencesCaptionBackgroundEnum.translucent;
        case r'solid': return DevicePreferencesCaptionBackgroundEnum.solid;
        case r'none': return DevicePreferencesCaptionBackgroundEnum.none;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [DevicePreferencesCaptionBackgroundEnumTypeTransformer] instance.
  static DevicePreferencesCaptionBackgroundEnumTypeTransformer? _instance;
}


