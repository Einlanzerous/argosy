//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EpisodeSummary {
  /// Returns a new [EpisodeSummary] instance.
  EpisodeSummary({
    required this.id,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.stillUrl,
    this.mediaItemId,
    this.durationSeconds,
    this.positionSeconds,
    this.watched,
  });

  String id;

  int episodeNumber;

  String? title;

  /// Per-episode synopsis from the metadata provider.
  String? overview;

  /// Episode still (16:9 landscape) image URL, or null when none.
  String? stillUrl;

  /// Backing file. Several episodes sharing one mediaItemId are a single combined rip.
  String? mediaItemId;

  num? durationSeconds;

  /// Current profile's resume position.
  num? positionSeconds;

  bool? watched;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EpisodeSummary &&
    other.id == id &&
    other.episodeNumber == episodeNumber &&
    other.title == title &&
    other.overview == overview &&
    other.stillUrl == stillUrl &&
    other.mediaItemId == mediaItemId &&
    other.durationSeconds == durationSeconds &&
    other.positionSeconds == positionSeconds &&
    other.watched == watched;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (episodeNumber.hashCode) +
    (title == null ? 0 : title!.hashCode) +
    (overview == null ? 0 : overview!.hashCode) +
    (stillUrl == null ? 0 : stillUrl!.hashCode) +
    (mediaItemId == null ? 0 : mediaItemId!.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (positionSeconds == null ? 0 : positionSeconds!.hashCode) +
    (watched == null ? 0 : watched!.hashCode);

  @override
  String toString() => 'EpisodeSummary[id=$id, episodeNumber=$episodeNumber, title=$title, overview=$overview, stillUrl=$stillUrl, mediaItemId=$mediaItemId, durationSeconds=$durationSeconds, positionSeconds=$positionSeconds, watched=$watched]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'episodeNumber'] = this.episodeNumber;
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
    }
    if (this.overview != null) {
      json[r'overview'] = this.overview;
    } else {
      json[r'overview'] = null;
    }
    if (this.stillUrl != null) {
      json[r'stillUrl'] = this.stillUrl;
    } else {
      json[r'stillUrl'] = null;
    }
    if (this.mediaItemId != null) {
      json[r'mediaItemId'] = this.mediaItemId;
    } else {
      json[r'mediaItemId'] = null;
    }
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
    if (this.positionSeconds != null) {
      json[r'positionSeconds'] = this.positionSeconds;
    } else {
      json[r'positionSeconds'] = null;
    }
    if (this.watched != null) {
      json[r'watched'] = this.watched;
    } else {
      json[r'watched'] = null;
    }
    return json;
  }

  /// Returns a new [EpisodeSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static EpisodeSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "EpisodeSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "EpisodeSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'episodeNumber'), 'Required key "EpisodeSummary[episodeNumber]" is missing from JSON.');
        assert(json[r'episodeNumber'] != null, 'Required key "EpisodeSummary[episodeNumber]" has a null value in JSON.');
        return true;
      }());

      return EpisodeSummary(
        id: mapValueOfType<String>(json, r'id')!,
        episodeNumber: mapValueOfType<int>(json, r'episodeNumber')!,
        title: mapValueOfType<String>(json, r'title'),
        overview: mapValueOfType<String>(json, r'overview'),
        stillUrl: mapValueOfType<String>(json, r'stillUrl'),
        mediaItemId: mapValueOfType<String>(json, r'mediaItemId'),
        durationSeconds: json[r'durationSeconds'] == null
            ? null
            : num.parse('${json[r'durationSeconds']}'),
        positionSeconds: json[r'positionSeconds'] == null
            ? null
            : num.parse('${json[r'positionSeconds']}'),
        watched: mapValueOfType<bool>(json, r'watched'),
      );
    }
    return null;
  }

  static List<EpisodeSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EpisodeSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EpisodeSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EpisodeSummary> mapFromJson(dynamic json) {
    final map = <String, EpisodeSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EpisodeSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of EpisodeSummary-objects as value to a dart map
  static Map<String, List<EpisodeSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EpisodeSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EpisodeSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'episodeNumber',
  };
}

