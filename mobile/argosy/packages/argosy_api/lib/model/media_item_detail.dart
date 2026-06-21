//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class MediaItemDetail {
  /// Returns a new [MediaItemDetail] instance.
  MediaItemDetail({
    required this.id,
    required this.kind,
    required this.title,
    this.year,
    this.overview,
    this.genres = const [],
    this.posterUrl,
    this.backdropUrl,
    this.durationSeconds,
    this.container,
    required this.filePath,
    required this.reviewRequired,
    this.tags = const [],
    this.rating,
    this.labels = const [],
  });

  String id;

  String kind;

  String title;

  int? year;

  String? overview;

  List<String> genres;

  String? posterUrl;

  /// Landscape backdrop for full-screen heroes; falls back to posterUrl.
  String? backdropUrl;

  num? durationSeconds;

  String? container;

  String filePath;

  bool reviewRequired;

  List<String> tags;

  /// Effective provider rating, 0–10.
  num? rating;

  /// The calling profile's custom labels on this item.
  List<String> labels;

  @override
  bool operator ==(Object other) => identical(this, other) || other is MediaItemDetail &&
    other.id == id &&
    other.kind == kind &&
    other.title == title &&
    other.year == year &&
    other.overview == overview &&
    _deepEquality.equals(other.genres, genres) &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    other.durationSeconds == durationSeconds &&
    other.container == container &&
    other.filePath == filePath &&
    other.reviewRequired == reviewRequired &&
    _deepEquality.equals(other.tags, tags) &&
    other.rating == rating &&
    _deepEquality.equals(other.labels, labels);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (kind.hashCode) +
    (title.hashCode) +
    (year == null ? 0 : year!.hashCode) +
    (overview == null ? 0 : overview!.hashCode) +
    (genres.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (container == null ? 0 : container!.hashCode) +
    (filePath.hashCode) +
    (reviewRequired.hashCode) +
    (tags.hashCode) +
    (rating == null ? 0 : rating!.hashCode) +
    (labels.hashCode);

  @override
  String toString() => 'MediaItemDetail[id=$id, kind=$kind, title=$title, year=$year, overview=$overview, genres=$genres, posterUrl=$posterUrl, backdropUrl=$backdropUrl, durationSeconds=$durationSeconds, container=$container, filePath=$filePath, reviewRequired=$reviewRequired, tags=$tags, rating=$rating, labels=$labels]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'kind'] = this.kind;
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
      json[r'genres'] = this.genres;
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
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
    if (this.container != null) {
      json[r'container'] = this.container;
    } else {
      json[r'container'] = null;
    }
      json[r'filePath'] = this.filePath;
      json[r'reviewRequired'] = this.reviewRequired;
      json[r'tags'] = this.tags;
    if (this.rating != null) {
      json[r'rating'] = this.rating;
    } else {
      json[r'rating'] = null;
    }
      json[r'labels'] = this.labels;
    return json;
  }

  /// Returns a new [MediaItemDetail] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MediaItemDetail? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "MediaItemDetail[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "MediaItemDetail[id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "MediaItemDetail[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "MediaItemDetail[kind]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "MediaItemDetail[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "MediaItemDetail[title]" has a null value in JSON.');
        assert(json.containsKey(r'filePath'), 'Required key "MediaItemDetail[filePath]" is missing from JSON.');
        assert(json[r'filePath'] != null, 'Required key "MediaItemDetail[filePath]" has a null value in JSON.');
        assert(json.containsKey(r'reviewRequired'), 'Required key "MediaItemDetail[reviewRequired]" is missing from JSON.');
        assert(json[r'reviewRequired'] != null, 'Required key "MediaItemDetail[reviewRequired]" has a null value in JSON.');
        assert(json.containsKey(r'tags'), 'Required key "MediaItemDetail[tags]" is missing from JSON.');
        assert(json[r'tags'] != null, 'Required key "MediaItemDetail[tags]" has a null value in JSON.');
        return true;
      }());

      return MediaItemDetail(
        id: mapValueOfType<String>(json, r'id')!,
        kind: mapValueOfType<String>(json, r'kind')!,
        title: mapValueOfType<String>(json, r'title')!,
        year: mapValueOfType<int>(json, r'year'),
        overview: mapValueOfType<String>(json, r'overview'),
        genres: json[r'genres'] is Iterable
            ? (json[r'genres'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
        container: mapValueOfType<String>(json, r'container'),
        filePath: mapValueOfType<String>(json, r'filePath')!,
        reviewRequired: mapValueOfType<bool>(json, r'reviewRequired')!,
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        rating: json[r'rating'] == null
            ? null
            : num.parse('${json[r'rating']}'),
        labels: json[r'labels'] is Iterable
            ? (json[r'labels'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<MediaItemDetail> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <MediaItemDetail>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MediaItemDetail.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MediaItemDetail> mapFromJson(dynamic json) {
    final map = <String, MediaItemDetail>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MediaItemDetail.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MediaItemDetail-objects as value to a dart map
  static Map<String, List<MediaItemDetail>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<MediaItemDetail>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MediaItemDetail.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'kind',
    'title',
    'filePath',
    'reviewRequired',
    'tags',
  };
}

