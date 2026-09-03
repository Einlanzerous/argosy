//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UnmappedSeason {
  /// Returns a new [UnmappedSeason] instance.
  UnmappedSeason({
    required this.seriesId,
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodes,
  });

  String seriesId;

  String seriesTitle;

  /// The season number as it appears on disk.
  int seasonNumber;

  /// Episode rows left without provider metadata.
  int episodes;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UnmappedSeason &&
    other.seriesId == seriesId &&
    other.seriesTitle == seriesTitle &&
    other.seasonNumber == seasonNumber &&
    other.episodes == episodes;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (seriesId.hashCode) +
    (seriesTitle.hashCode) +
    (seasonNumber.hashCode) +
    (episodes.hashCode);

  @override
  String toString() => 'UnmappedSeason[seriesId=$seriesId, seriesTitle=$seriesTitle, seasonNumber=$seasonNumber, episodes=$episodes]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'seriesId'] = this.seriesId;
      json[r'seriesTitle'] = this.seriesTitle;
      json[r'seasonNumber'] = this.seasonNumber;
      json[r'episodes'] = this.episodes;
    return json;
  }

  /// Returns a new [UnmappedSeason] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UnmappedSeason? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'seriesId'), 'Required key "UnmappedSeason[seriesId]" is missing from JSON.');
        assert(json[r'seriesId'] != null, 'Required key "UnmappedSeason[seriesId]" has a null value in JSON.');
        assert(json.containsKey(r'seriesTitle'), 'Required key "UnmappedSeason[seriesTitle]" is missing from JSON.');
        assert(json[r'seriesTitle'] != null, 'Required key "UnmappedSeason[seriesTitle]" has a null value in JSON.');
        assert(json.containsKey(r'seasonNumber'), 'Required key "UnmappedSeason[seasonNumber]" is missing from JSON.');
        assert(json[r'seasonNumber'] != null, 'Required key "UnmappedSeason[seasonNumber]" has a null value in JSON.');
        assert(json.containsKey(r'episodes'), 'Required key "UnmappedSeason[episodes]" is missing from JSON.');
        assert(json[r'episodes'] != null, 'Required key "UnmappedSeason[episodes]" has a null value in JSON.');
        return true;
      }());

      return UnmappedSeason(
        seriesId: mapValueOfType<String>(json, r'seriesId')!,
        seriesTitle: mapValueOfType<String>(json, r'seriesTitle')!,
        seasonNumber: mapValueOfType<int>(json, r'seasonNumber')!,
        episodes: mapValueOfType<int>(json, r'episodes')!,
      );
    }
    return null;
  }

  static List<UnmappedSeason> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnmappedSeason>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnmappedSeason.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UnmappedSeason> mapFromJson(dynamic json) {
    final map = <String, UnmappedSeason>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UnmappedSeason.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UnmappedSeason-objects as value to a dart map
  static Map<String, List<UnmappedSeason>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UnmappedSeason>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UnmappedSeason.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'seriesId',
    'seriesTitle',
    'seasonNumber',
    'episodes',
  };
}

