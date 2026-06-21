//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SearchResults {
  /// Returns a new [SearchResults] instance.
  SearchResults({
    this.movies = const [],
    this.series = const [],
  });

  List<MediaItemSummary> movies;

  List<SeriesSummary> series;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SearchResults &&
    _deepEquality.equals(other.movies, movies) &&
    _deepEquality.equals(other.series, series);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (movies.hashCode) +
    (series.hashCode);

  @override
  String toString() => 'SearchResults[movies=$movies, series=$series]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'movies'] = this.movies;
      json[r'series'] = this.series;
    return json;
  }

  /// Returns a new [SearchResults] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SearchResults? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'movies'), 'Required key "SearchResults[movies]" is missing from JSON.');
        assert(json[r'movies'] != null, 'Required key "SearchResults[movies]" has a null value in JSON.');
        assert(json.containsKey(r'series'), 'Required key "SearchResults[series]" is missing from JSON.');
        assert(json[r'series'] != null, 'Required key "SearchResults[series]" has a null value in JSON.');
        return true;
      }());

      return SearchResults(
        movies: MediaItemSummary.listFromJson(json[r'movies']),
        series: SeriesSummary.listFromJson(json[r'series']),
      );
    }
    return null;
  }

  static List<SearchResults> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SearchResults>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SearchResults.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SearchResults> mapFromJson(dynamic json) {
    final map = <String, SearchResults>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SearchResults.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SearchResults-objects as value to a dart map
  static Map<String, List<SearchResults>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SearchResults>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SearchResults.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'movies',
    'series',
  };
}

