//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SeasonSummary {
  /// Returns a new [SeasonSummary] instance.
  SeasonSummary({
    required this.id,
    required this.seasonNumber,
    this.title,
    this.episodes = const [],
  });

  String id;

  int seasonNumber;

  String? title;

  List<EpisodeSummary> episodes;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SeasonSummary &&
    other.id == id &&
    other.seasonNumber == seasonNumber &&
    other.title == title &&
    _deepEquality.equals(other.episodes, episodes);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (seasonNumber.hashCode) +
    (title == null ? 0 : title!.hashCode) +
    (episodes.hashCode);

  @override
  String toString() => 'SeasonSummary[id=$id, seasonNumber=$seasonNumber, title=$title, episodes=$episodes]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'seasonNumber'] = this.seasonNumber;
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
    }
      json[r'episodes'] = this.episodes;
    return json;
  }

  /// Returns a new [SeasonSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SeasonSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "SeasonSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "SeasonSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'seasonNumber'), 'Required key "SeasonSummary[seasonNumber]" is missing from JSON.');
        assert(json[r'seasonNumber'] != null, 'Required key "SeasonSummary[seasonNumber]" has a null value in JSON.');
        assert(json.containsKey(r'episodes'), 'Required key "SeasonSummary[episodes]" is missing from JSON.');
        assert(json[r'episodes'] != null, 'Required key "SeasonSummary[episodes]" has a null value in JSON.');
        return true;
      }());

      return SeasonSummary(
        id: mapValueOfType<String>(json, r'id')!,
        seasonNumber: mapValueOfType<int>(json, r'seasonNumber')!,
        title: mapValueOfType<String>(json, r'title'),
        episodes: EpisodeSummary.listFromJson(json[r'episodes']),
      );
    }
    return null;
  }

  static List<SeasonSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SeasonSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SeasonSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SeasonSummary> mapFromJson(dynamic json) {
    final map = <String, SeasonSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SeasonSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SeasonSummary-objects as value to a dart map
  static Map<String, List<SeasonSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SeasonSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SeasonSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'seasonNumber',
    'episodes',
  };
}

