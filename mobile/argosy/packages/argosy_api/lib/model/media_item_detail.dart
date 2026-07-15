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
    this.rating,
    this.cast = const [],
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
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

  /// Effective provider rating, 0–10.
  num? rating;

  /// Top-billed cast names (plus the director, for films) from the metadata provider. Omitted when none.
  List<String> cast;

  /// Parent series title, set only when this media item backs one or more episodes. Drives the player's now-playing header (ARGY-134).
  String? seriesTitle;

  /// Season number of the episode this item backs, when applicable.
  int? seasonNumber;

  /// Episode number this item backs; for a combined rip it's the first episode of the span.
  int? episodeNumber;

  /// Per-episode title (TMDB), when resolved. May still be the SxxExx filename fallback — clients should sanitize before display.
  String? episodeTitle;

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
    other.rating == rating &&
    _deepEquality.equals(other.cast, cast) &&
    other.seriesTitle == seriesTitle &&
    other.seasonNumber == seasonNumber &&
    other.episodeNumber == episodeNumber &&
    other.episodeTitle == episodeTitle;

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
    (rating == null ? 0 : rating!.hashCode) +
    (cast.hashCode) +
    (seriesTitle == null ? 0 : seriesTitle!.hashCode) +
    (seasonNumber == null ? 0 : seasonNumber!.hashCode) +
    (episodeNumber == null ? 0 : episodeNumber!.hashCode) +
    (episodeTitle == null ? 0 : episodeTitle!.hashCode);

  @override
  String toString() => 'MediaItemDetail[id=$id, kind=$kind, title=$title, year=$year, overview=$overview, genres=$genres, posterUrl=$posterUrl, backdropUrl=$backdropUrl, durationSeconds=$durationSeconds, container=$container, filePath=$filePath, reviewRequired=$reviewRequired, rating=$rating, cast=$cast, seriesTitle=$seriesTitle, seasonNumber=$seasonNumber, episodeNumber=$episodeNumber, episodeTitle=$episodeTitle]';

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
    if (this.rating != null) {
      json[r'rating'] = this.rating;
    } else {
      json[r'rating'] = null;
    }
      json[r'cast'] = this.cast;
    if (this.seriesTitle != null) {
      json[r'seriesTitle'] = this.seriesTitle;
    } else {
      json[r'seriesTitle'] = null;
    }
    if (this.seasonNumber != null) {
      json[r'seasonNumber'] = this.seasonNumber;
    } else {
      json[r'seasonNumber'] = null;
    }
    if (this.episodeNumber != null) {
      json[r'episodeNumber'] = this.episodeNumber;
    } else {
      json[r'episodeNumber'] = null;
    }
    if (this.episodeTitle != null) {
      json[r'episodeTitle'] = this.episodeTitle;
    } else {
      json[r'episodeTitle'] = null;
    }
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
        rating: json[r'rating'] == null
            ? null
            : num.parse('${json[r'rating']}'),
        cast: json[r'cast'] is Iterable
            ? (json[r'cast'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        seriesTitle: mapValueOfType<String>(json, r'seriesTitle'),
        seasonNumber: mapValueOfType<int>(json, r'seasonNumber'),
        episodeNumber: mapValueOfType<int>(json, r'episodeNumber'),
        episodeTitle: mapValueOfType<String>(json, r'episodeTitle'),
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
  };
}

