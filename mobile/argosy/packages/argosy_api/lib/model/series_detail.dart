//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SeriesDetail {
  /// Returns a new [SeriesDetail] instance.
  SeriesDetail({
    required this.id,
    required this.title,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.seasons = const [],
    this.tags = const [],
    this.labels = const [],
  });

  String id;

  String title;

  int? year;

  String? overview;

  String? posterUrl;

  /// Landscape backdrop for full-screen heroes; falls back to posterUrl.
  String? backdropUrl;

  List<SeasonSummary> seasons;

  List<String> tags;

  /// The calling profile's custom labels on this series.
  List<String> labels;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SeriesDetail &&
    other.id == id &&
    other.title == title &&
    other.year == year &&
    other.overview == overview &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    _deepEquality.equals(other.seasons, seasons) &&
    _deepEquality.equals(other.tags, tags) &&
    _deepEquality.equals(other.labels, labels);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (title.hashCode) +
    (year == null ? 0 : year!.hashCode) +
    (overview == null ? 0 : overview!.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (seasons.hashCode) +
    (tags.hashCode) +
    (labels.hashCode);

  @override
  String toString() => 'SeriesDetail[id=$id, title=$title, year=$year, overview=$overview, posterUrl=$posterUrl, backdropUrl=$backdropUrl, seasons=$seasons, tags=$tags, labels=$labels]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'title'] = this.title;
    if (this.year != null) {
      json[r'year'] = this.year;
    } else {
      json[r'year'] = null;
    }
    if (this.overview != null) {
      json[r'overview'] = this.overview;
    } else {
      json[r'overview'] = null;
    }
    if (this.posterUrl != null) {
      json[r'posterUrl'] = this.posterUrl;
    } else {
      json[r'posterUrl'] = null;
    }
    if (this.backdropUrl != null) {
      json[r'backdropUrl'] = this.backdropUrl;
    } else {
      json[r'backdropUrl'] = null;
    }
      json[r'seasons'] = this.seasons;
      json[r'tags'] = this.tags;
      json[r'labels'] = this.labels;
    return json;
  }

  /// Returns a new [SeriesDetail] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SeriesDetail? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "SeriesDetail[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "SeriesDetail[id]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "SeriesDetail[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "SeriesDetail[title]" has a null value in JSON.');
        assert(json.containsKey(r'seasons'), 'Required key "SeriesDetail[seasons]" is missing from JSON.');
        assert(json[r'seasons'] != null, 'Required key "SeriesDetail[seasons]" has a null value in JSON.');
        assert(json.containsKey(r'tags'), 'Required key "SeriesDetail[tags]" is missing from JSON.');
        assert(json[r'tags'] != null, 'Required key "SeriesDetail[tags]" has a null value in JSON.');
        return true;
      }());

      return SeriesDetail(
        id: mapValueOfType<String>(json, r'id')!,
        title: mapValueOfType<String>(json, r'title')!,
        year: mapValueOfType<int>(json, r'year'),
        overview: mapValueOfType<String>(json, r'overview'),
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        seasons: SeasonSummary.listFromJson(json[r'seasons']),
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        labels: json[r'labels'] is Iterable
            ? (json[r'labels'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<SeriesDetail> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SeriesDetail>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SeriesDetail.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SeriesDetail> mapFromJson(dynamic json) {
    final map = <String, SeriesDetail>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SeriesDetail.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SeriesDetail-objects as value to a dart map
  static Map<String, List<SeriesDetail>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SeriesDetail>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SeriesDetail.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'title',
    'seasons',
    'tags',
  };
}

