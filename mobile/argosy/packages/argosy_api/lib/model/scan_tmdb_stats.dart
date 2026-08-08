//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ScanTMDBStats {
  /// Returns a new [ScanTMDBStats] instance.
  ScanTMDBStats({
    required this.requests,
    required this.retries,
    required this.throttled,
    required this.exhausted,
    required this.artworkRequests,
    required this.artworkRetries,
    required this.artworkThrottled,
    required this.artworkExhausted,
    required this.rateLimit,
    required this.configuredRate,
  });

  /// API round-trips sent this sweep, retries included.
  int requests;

  /// API round-trips retried after a 429, 5xx, or transport error.
  int retries;

  /// 429 responses from the API — it asking for a slower rate. Not a subset of retries: a request's final attempt is counted here but was never retried, so this can exceed retries.
  int throttled;

  /// API requests that used every retry and failed permanently. Each one is a title that went without metadata; non-zero warrants a re-match.
  int exhausted;

  /// Image-CDN round-trips sent this sweep, retries included.
  int artworkRequests;

  /// Image-CDN round-trips retried after a 429, 5xx, or transport error.
  int artworkRetries;

  /// 429 responses from the image CDN. Reported but deliberately not acted on — the CDN does not steer the shared rate limit, which the API owns.
  int artworkThrottled;

  /// Artwork downloads that failed permanently. These are missing posters, backdrops or episode stills — the title itself still has its metadata.
  int artworkExhausted;

  /// The limiter's current ceiling in req/s, shared by both surfaces but steered only by the API. Below configuredRate means adaptive throttling has backed off after sustained 429s from the API; it recovers on its own as clean responses come back.
  double rateLimit;

  /// The operator-configured ceiling in req/s (ARGOSY_TMDB_RATE).
  double configuredRate;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ScanTMDBStats &&
    other.requests == requests &&
    other.retries == retries &&
    other.throttled == throttled &&
    other.exhausted == exhausted &&
    other.artworkRequests == artworkRequests &&
    other.artworkRetries == artworkRetries &&
    other.artworkThrottled == artworkThrottled &&
    other.artworkExhausted == artworkExhausted &&
    other.rateLimit == rateLimit &&
    other.configuredRate == configuredRate;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requests.hashCode) +
    (retries.hashCode) +
    (throttled.hashCode) +
    (exhausted.hashCode) +
    (artworkRequests.hashCode) +
    (artworkRetries.hashCode) +
    (artworkThrottled.hashCode) +
    (artworkExhausted.hashCode) +
    (rateLimit.hashCode) +
    (configuredRate.hashCode);

  @override
  String toString() => 'ScanTMDBStats[requests=$requests, retries=$retries, throttled=$throttled, exhausted=$exhausted, artworkRequests=$artworkRequests, artworkRetries=$artworkRetries, artworkThrottled=$artworkThrottled, artworkExhausted=$artworkExhausted, rateLimit=$rateLimit, configuredRate=$configuredRate]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requests'] = this.requests;
      json[r'retries'] = this.retries;
      json[r'throttled'] = this.throttled;
      json[r'exhausted'] = this.exhausted;
      json[r'artworkRequests'] = this.artworkRequests;
      json[r'artworkRetries'] = this.artworkRetries;
      json[r'artworkThrottled'] = this.artworkThrottled;
      json[r'artworkExhausted'] = this.artworkExhausted;
      json[r'rateLimit'] = this.rateLimit;
      json[r'configuredRate'] = this.configuredRate;
    return json;
  }

  /// Returns a new [ScanTMDBStats] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ScanTMDBStats? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'requests'), 'Required key "ScanTMDBStats[requests]" is missing from JSON.');
        assert(json[r'requests'] != null, 'Required key "ScanTMDBStats[requests]" has a null value in JSON.');
        assert(json.containsKey(r'retries'), 'Required key "ScanTMDBStats[retries]" is missing from JSON.');
        assert(json[r'retries'] != null, 'Required key "ScanTMDBStats[retries]" has a null value in JSON.');
        assert(json.containsKey(r'throttled'), 'Required key "ScanTMDBStats[throttled]" is missing from JSON.');
        assert(json[r'throttled'] != null, 'Required key "ScanTMDBStats[throttled]" has a null value in JSON.');
        assert(json.containsKey(r'exhausted'), 'Required key "ScanTMDBStats[exhausted]" is missing from JSON.');
        assert(json[r'exhausted'] != null, 'Required key "ScanTMDBStats[exhausted]" has a null value in JSON.');
        assert(json.containsKey(r'artworkRequests'), 'Required key "ScanTMDBStats[artworkRequests]" is missing from JSON.');
        assert(json[r'artworkRequests'] != null, 'Required key "ScanTMDBStats[artworkRequests]" has a null value in JSON.');
        assert(json.containsKey(r'artworkRetries'), 'Required key "ScanTMDBStats[artworkRetries]" is missing from JSON.');
        assert(json[r'artworkRetries'] != null, 'Required key "ScanTMDBStats[artworkRetries]" has a null value in JSON.');
        assert(json.containsKey(r'artworkThrottled'), 'Required key "ScanTMDBStats[artworkThrottled]" is missing from JSON.');
        assert(json[r'artworkThrottled'] != null, 'Required key "ScanTMDBStats[artworkThrottled]" has a null value in JSON.');
        assert(json.containsKey(r'artworkExhausted'), 'Required key "ScanTMDBStats[artworkExhausted]" is missing from JSON.');
        assert(json[r'artworkExhausted'] != null, 'Required key "ScanTMDBStats[artworkExhausted]" has a null value in JSON.');
        assert(json.containsKey(r'rateLimit'), 'Required key "ScanTMDBStats[rateLimit]" is missing from JSON.');
        assert(json[r'rateLimit'] != null, 'Required key "ScanTMDBStats[rateLimit]" has a null value in JSON.');
        assert(json.containsKey(r'configuredRate'), 'Required key "ScanTMDBStats[configuredRate]" is missing from JSON.');
        assert(json[r'configuredRate'] != null, 'Required key "ScanTMDBStats[configuredRate]" has a null value in JSON.');
        return true;
      }());

      return ScanTMDBStats(
        requests: mapValueOfType<int>(json, r'requests')!,
        retries: mapValueOfType<int>(json, r'retries')!,
        throttled: mapValueOfType<int>(json, r'throttled')!,
        exhausted: mapValueOfType<int>(json, r'exhausted')!,
        artworkRequests: mapValueOfType<int>(json, r'artworkRequests')!,
        artworkRetries: mapValueOfType<int>(json, r'artworkRetries')!,
        artworkThrottled: mapValueOfType<int>(json, r'artworkThrottled')!,
        artworkExhausted: mapValueOfType<int>(json, r'artworkExhausted')!,
        rateLimit: mapValueOfType<double>(json, r'rateLimit')!,
        configuredRate: mapValueOfType<double>(json, r'configuredRate')!,
      );
    }
    return null;
  }

  static List<ScanTMDBStats> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ScanTMDBStats>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ScanTMDBStats.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ScanTMDBStats> mapFromJson(dynamic json) {
    final map = <String, ScanTMDBStats>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ScanTMDBStats.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ScanTMDBStats-objects as value to a dart map
  static Map<String, List<ScanTMDBStats>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ScanTMDBStats>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ScanTMDBStats.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'requests',
    'retries',
    'throttled',
    'exhausted',
    'artworkRequests',
    'artworkRetries',
    'artworkThrottled',
    'artworkExhausted',
    'rateLimit',
    'configuredRate',
  };
}

