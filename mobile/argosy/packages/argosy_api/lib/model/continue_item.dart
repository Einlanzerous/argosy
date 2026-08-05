//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ContinueItem {
  /// Returns a new [ContinueItem] instance.
  ContinueItem({
    required this.id,
    required this.kind,
    required this.title,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    required this.positionSeconds,
    this.durationSeconds,
    required this.percent,
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.lastPlayedDevice,
  });

  String id;

  String kind;

  String title;

  int? year;

  String? posterUrl;

  /// Landscape backdrop for full-screen heroes; falls back to posterUrl.
  String? backdropUrl;

  num positionSeconds;

  num? durationSeconds;

  num percent;

  String? seriesId;

  String? seriesTitle;

  /// Season number when this item is an episode; null for films. Named to match OnDeckItem so clients can share the \"S1 · E1\" formatting. 
  int? seasonNumber;

  /// Episode number when this item is an episode; null for films.
  int? episodeNumber;

  /// The episode's own title (e.g. \"The World of Swords\"). Distinct from `title`, which is the media item's — filename-derived for episodes, and therefore usually a repeat of the series name plus release tags (ARGY-176). Null for films, which carry their name in `title`. 
  String? episodeTitle;

  /// The deck that last owned this playhead, set only when it differs from the requesting device — drives the cross-device \"⇄ left off on\" pill (ARGY-98).
  DeviceRef? lastPlayedDevice;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ContinueItem &&
    other.id == id &&
    other.kind == kind &&
    other.title == title &&
    other.year == year &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    other.positionSeconds == positionSeconds &&
    other.durationSeconds == durationSeconds &&
    other.percent == percent &&
    other.seriesId == seriesId &&
    other.seriesTitle == seriesTitle &&
    other.seasonNumber == seasonNumber &&
    other.episodeNumber == episodeNumber &&
    other.episodeTitle == episodeTitle &&
    other.lastPlayedDevice == lastPlayedDevice;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (kind.hashCode) +
    (title.hashCode) +
    (year == null ? 0 : year!.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (positionSeconds.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (percent.hashCode) +
    (seriesId == null ? 0 : seriesId!.hashCode) +
    (seriesTitle == null ? 0 : seriesTitle!.hashCode) +
    (seasonNumber == null ? 0 : seasonNumber!.hashCode) +
    (episodeNumber == null ? 0 : episodeNumber!.hashCode) +
    (episodeTitle == null ? 0 : episodeTitle!.hashCode) +
    (lastPlayedDevice == null ? 0 : lastPlayedDevice!.hashCode);

  @override
  String toString() => 'ContinueItem[id=$id, kind=$kind, title=$title, year=$year, posterUrl=$posterUrl, backdropUrl=$backdropUrl, positionSeconds=$positionSeconds, durationSeconds=$durationSeconds, percent=$percent, seriesId=$seriesId, seriesTitle=$seriesTitle, seasonNumber=$seasonNumber, episodeNumber=$episodeNumber, episodeTitle=$episodeTitle, lastPlayedDevice=$lastPlayedDevice]';

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
      json[r'positionSeconds'] = this.positionSeconds;
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
      json[r'percent'] = this.percent;
    if (this.seriesId != null) {
      json[r'seriesId'] = this.seriesId;
    } else {
      json[r'seriesId'] = null;
    }
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
    if (this.lastPlayedDevice != null) {
      json[r'lastPlayedDevice'] = this.lastPlayedDevice;
    } else {
      json[r'lastPlayedDevice'] = null;
    }
    return json;
  }

  /// Returns a new [ContinueItem] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ContinueItem? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "ContinueItem[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "ContinueItem[id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "ContinueItem[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "ContinueItem[kind]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "ContinueItem[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "ContinueItem[title]" has a null value in JSON.');
        assert(json.containsKey(r'positionSeconds'), 'Required key "ContinueItem[positionSeconds]" is missing from JSON.');
        assert(json[r'positionSeconds'] != null, 'Required key "ContinueItem[positionSeconds]" has a null value in JSON.');
        assert(json.containsKey(r'percent'), 'Required key "ContinueItem[percent]" is missing from JSON.');
        assert(json[r'percent'] != null, 'Required key "ContinueItem[percent]" has a null value in JSON.');
        return true;
      }());

      return ContinueItem(
        id: mapValueOfType<String>(json, r'id')!,
        kind: mapValueOfType<String>(json, r'kind')!,
        title: mapValueOfType<String>(json, r'title')!,
        year: mapValueOfType<int>(json, r'year'),
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        positionSeconds: num.parse('${json[r'positionSeconds']}'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
        percent: num.parse('${json[r'percent']}'),
        seriesId: mapValueOfType<String>(json, r'seriesId'),
        seriesTitle: mapValueOfType<String>(json, r'seriesTitle'),
        seasonNumber: mapValueOfType<int>(json, r'seasonNumber'),
        episodeNumber: mapValueOfType<int>(json, r'episodeNumber'),
        episodeTitle: mapValueOfType<String>(json, r'episodeTitle'),
        lastPlayedDevice: DeviceRef.fromJson(json[r'lastPlayedDevice']),
      );
    }
    return null;
  }

  static List<ContinueItem> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ContinueItem>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ContinueItem.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ContinueItem> mapFromJson(dynamic json) {
    final map = <String, ContinueItem>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ContinueItem.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ContinueItem-objects as value to a dart map
  static Map<String, List<ContinueItem>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ContinueItem>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ContinueItem.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'kind',
    'title',
    'positionSeconds',
    'percent',
  };
}

