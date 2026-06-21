//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class OnDeckItem {
  /// Returns a new [OnDeckItem] instance.
  OnDeckItem({
    required this.id,
    required this.seriesId,
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.posterUrl,
    this.backdropUrl,
    this.durationSeconds,
  });

  /// The episode's playable media-item id.
  String id;

  String seriesId;

  String seriesTitle;

  int seasonNumber;

  int episodeNumber;

  /// Episode title.
  String? title;

  String? posterUrl;

  /// Landscape backdrop; falls back to posterUrl.
  String? backdropUrl;

  num? durationSeconds;

  @override
  bool operator ==(Object other) => identical(this, other) || other is OnDeckItem &&
    other.id == id &&
    other.seriesId == seriesId &&
    other.seriesTitle == seriesTitle &&
    other.seasonNumber == seasonNumber &&
    other.episodeNumber == episodeNumber &&
    other.title == title &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    other.durationSeconds == durationSeconds;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (seriesId.hashCode) +
    (seriesTitle.hashCode) +
    (seasonNumber.hashCode) +
    (episodeNumber.hashCode) +
    (title == null ? 0 : title!.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode);

  @override
  String toString() => 'OnDeckItem[id=$id, seriesId=$seriesId, seriesTitle=$seriesTitle, seasonNumber=$seasonNumber, episodeNumber=$episodeNumber, title=$title, posterUrl=$posterUrl, backdropUrl=$backdropUrl, durationSeconds=$durationSeconds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'seriesId'] = this.seriesId;
      json[r'seriesTitle'] = this.seriesTitle;
      json[r'seasonNumber'] = this.seasonNumber;
      json[r'episodeNumber'] = this.episodeNumber;
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
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
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
    return json;
  }

  /// Returns a new [OnDeckItem] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static OnDeckItem? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "OnDeckItem[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "OnDeckItem[id]" has a null value in JSON.');
        assert(json.containsKey(r'seriesId'), 'Required key "OnDeckItem[seriesId]" is missing from JSON.');
        assert(json[r'seriesId'] != null, 'Required key "OnDeckItem[seriesId]" has a null value in JSON.');
        assert(json.containsKey(r'seriesTitle'), 'Required key "OnDeckItem[seriesTitle]" is missing from JSON.');
        assert(json[r'seriesTitle'] != null, 'Required key "OnDeckItem[seriesTitle]" has a null value in JSON.');
        assert(json.containsKey(r'seasonNumber'), 'Required key "OnDeckItem[seasonNumber]" is missing from JSON.');
        assert(json[r'seasonNumber'] != null, 'Required key "OnDeckItem[seasonNumber]" has a null value in JSON.');
        assert(json.containsKey(r'episodeNumber'), 'Required key "OnDeckItem[episodeNumber]" is missing from JSON.');
        assert(json[r'episodeNumber'] != null, 'Required key "OnDeckItem[episodeNumber]" has a null value in JSON.');
        return true;
      }());

      return OnDeckItem(
        id: mapValueOfType<String>(json, r'id')!,
        seriesId: mapValueOfType<String>(json, r'seriesId')!,
        seriesTitle: mapValueOfType<String>(json, r'seriesTitle')!,
        seasonNumber: mapValueOfType<int>(json, r'seasonNumber')!,
        episodeNumber: mapValueOfType<int>(json, r'episodeNumber')!,
        title: mapValueOfType<String>(json, r'title'),
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
      );
    }
    return null;
  }

  static List<OnDeckItem> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <OnDeckItem>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = OnDeckItem.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, OnDeckItem> mapFromJson(dynamic json) {
    final map = <String, OnDeckItem>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = OnDeckItem.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of OnDeckItem-objects as value to a dart map
  static Map<String, List<OnDeckItem>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<OnDeckItem>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = OnDeckItem.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'seriesId',
    'seriesTitle',
    'seasonNumber',
    'episodeNumber',
  };
}

