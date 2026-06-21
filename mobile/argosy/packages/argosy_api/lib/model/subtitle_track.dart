//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SubtitleTrack {
  /// Returns a new [SubtitleTrack] instance.
  SubtitleTrack({
    required this.id,
    required this.source_,
    required this.language,
    required this.label,
    required this.forced,
    required this.default_,
  });

  /// Track handle for the WebVTT endpoint (e.g. \"embedded:3\", \"os:12345\").
  String id;

  SubtitleTrackSource_Enum source_;

  /// BCP-47 language code (e.g. \"en\"), or \"und\" when unknown.
  String language;

  /// Human-readable label for the subtitle picker.
  String label;

  bool forced;

  bool default_;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SubtitleTrack &&
    other.id == id &&
    other.source_ == source_ &&
    other.language == language &&
    other.label == label &&
    other.forced == forced &&
    other.default_ == default_;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (source_.hashCode) +
    (language.hashCode) +
    (label.hashCode) +
    (forced.hashCode) +
    (default_.hashCode);

  @override
  String toString() => 'SubtitleTrack[id=$id, source_=$source_, language=$language, label=$label, forced=$forced, default_=$default_]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'source'] = this.source_;
      json[r'language'] = this.language;
      json[r'label'] = this.label;
      json[r'forced'] = this.forced;
      json[r'default'] = this.default_;
    return json;
  }

  /// Returns a new [SubtitleTrack] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SubtitleTrack? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "SubtitleTrack[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "SubtitleTrack[id]" has a null value in JSON.');
        assert(json.containsKey(r'source'), 'Required key "SubtitleTrack[source]" is missing from JSON.');
        assert(json[r'source'] != null, 'Required key "SubtitleTrack[source]" has a null value in JSON.');
        assert(json.containsKey(r'language'), 'Required key "SubtitleTrack[language]" is missing from JSON.');
        assert(json[r'language'] != null, 'Required key "SubtitleTrack[language]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "SubtitleTrack[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "SubtitleTrack[label]" has a null value in JSON.');
        assert(json.containsKey(r'forced'), 'Required key "SubtitleTrack[forced]" is missing from JSON.');
        assert(json[r'forced'] != null, 'Required key "SubtitleTrack[forced]" has a null value in JSON.');
        assert(json.containsKey(r'default'), 'Required key "SubtitleTrack[default]" is missing from JSON.');
        assert(json[r'default'] != null, 'Required key "SubtitleTrack[default]" has a null value in JSON.');
        return true;
      }());

      return SubtitleTrack(
        id: mapValueOfType<String>(json, r'id')!,
        source_: SubtitleTrackSource_Enum.fromJson(json[r'source'])!,
        language: mapValueOfType<String>(json, r'language')!,
        label: mapValueOfType<String>(json, r'label')!,
        forced: mapValueOfType<bool>(json, r'forced')!,
        default_: mapValueOfType<bool>(json, r'default')!,
      );
    }
    return null;
  }

  static List<SubtitleTrack> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SubtitleTrack>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SubtitleTrack.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SubtitleTrack> mapFromJson(dynamic json) {
    final map = <String, SubtitleTrack>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SubtitleTrack.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SubtitleTrack-objects as value to a dart map
  static Map<String, List<SubtitleTrack>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SubtitleTrack>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SubtitleTrack.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'source',
    'language',
    'label',
    'forced',
    'default',
  };
}


class SubtitleTrackSource_Enum {
  /// Instantiate a new enum with the provided [value].
  const SubtitleTrackSource_Enum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const embedded = SubtitleTrackSource_Enum._(r'embedded');
  static const opensubtitles = SubtitleTrackSource_Enum._(r'opensubtitles');

  /// List of all possible values in this [enum][SubtitleTrackSource_Enum].
  static const values = <SubtitleTrackSource_Enum>[
    embedded,
    opensubtitles,
  ];

  static SubtitleTrackSource_Enum? fromJson(dynamic value) => SubtitleTrackSource_EnumTypeTransformer().decode(value);

  static List<SubtitleTrackSource_Enum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SubtitleTrackSource_Enum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SubtitleTrackSource_Enum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SubtitleTrackSource_Enum] to String,
/// and [decode] dynamic data back to [SubtitleTrackSource_Enum].
class SubtitleTrackSource_EnumTypeTransformer {
  factory SubtitleTrackSource_EnumTypeTransformer() => _instance ??= const SubtitleTrackSource_EnumTypeTransformer._();

  const SubtitleTrackSource_EnumTypeTransformer._();

  String encode(SubtitleTrackSource_Enum data) => data.value;

  /// Decodes a [dynamic value][data] to a SubtitleTrackSource_Enum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SubtitleTrackSource_Enum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'embedded': return SubtitleTrackSource_Enum.embedded;
        case r'opensubtitles': return SubtitleTrackSource_Enum.opensubtitles;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [SubtitleTrackSource_EnumTypeTransformer] instance.
  static SubtitleTrackSource_EnumTypeTransformer? _instance;
}


