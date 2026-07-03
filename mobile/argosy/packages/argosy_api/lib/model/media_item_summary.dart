//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class MediaItemSummary {
  /// Returns a new [MediaItemSummary] instance.
  MediaItemSummary({
    required this.id,
    required this.kind,
    required this.title,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
  });

  String id;

  String kind;

  String title;

  int? year;

  String? posterUrl;

  /// Landscape backdrop for full-screen heroes; falls back to posterUrl.
  String? backdropUrl;

  /// Effective provider rating, 0–10.
  num? rating;

  @override
  bool operator ==(Object other) => identical(this, other) || other is MediaItemSummary &&
    other.id == id &&
    other.kind == kind &&
    other.title == title &&
    other.year == year &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    other.rating == rating;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (kind.hashCode) +
    (title.hashCode) +
    (year == null ? 0 : year!.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (rating == null ? 0 : rating!.hashCode);

  @override
  String toString() => 'MediaItemSummary[id=$id, kind=$kind, title=$title, year=$year, posterUrl=$posterUrl, backdropUrl=$backdropUrl, rating=$rating]';

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
    if (this.rating != null) {
      json[r'rating'] = this.rating;
    } else {
      json[r'rating'] = null;
    }
    return json;
  }

  /// Returns a new [MediaItemSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MediaItemSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "MediaItemSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "MediaItemSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "MediaItemSummary[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "MediaItemSummary[kind]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "MediaItemSummary[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "MediaItemSummary[title]" has a null value in JSON.');
        return true;
      }());

      return MediaItemSummary(
        id: mapValueOfType<String>(json, r'id')!,
        kind: mapValueOfType<String>(json, r'kind')!,
        title: mapValueOfType<String>(json, r'title')!,
        year: mapValueOfType<int>(json, r'year'),
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        rating: json[r'rating'] == null
            ? null
            : num.parse('${json[r'rating']}'),
      );
    }
    return null;
  }

  static List<MediaItemSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <MediaItemSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MediaItemSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MediaItemSummary> mapFromJson(dynamic json) {
    final map = <String, MediaItemSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MediaItemSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MediaItemSummary-objects as value to a dart map
  static Map<String, List<MediaItemSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<MediaItemSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MediaItemSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'kind',
    'title',
  };
}

