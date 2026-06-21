//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PlaybackSession {
  /// Returns a new [PlaybackSession] instance.
  PlaybackSession({
    required this.userId,
    required this.deviceId,
    required this.itemId,
    required this.positionSeconds,
    this.durationSeconds,
    required this.state,
    required this.startedAt,
    required this.lastSeen,
    this.encoder,
    this.method,
  });

  String userId;

  String deviceId;

  String itemId;

  double positionSeconds;

  double? durationSeconds;

  /// e.g. \"playing\"
  String state;

  DateTime startedAt;

  DateTime lastSeen;

  /// Encoder of the owned transcode session, if any.
  String? encoder;

  /// remux | transcode, if this session owns a transcode session.
  String? method;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PlaybackSession &&
    other.userId == userId &&
    other.deviceId == deviceId &&
    other.itemId == itemId &&
    other.positionSeconds == positionSeconds &&
    other.durationSeconds == durationSeconds &&
    other.state == state &&
    other.startedAt == startedAt &&
    other.lastSeen == lastSeen &&
    other.encoder == encoder &&
    other.method == method;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (userId.hashCode) +
    (deviceId.hashCode) +
    (itemId.hashCode) +
    (positionSeconds.hashCode) +
    (durationSeconds == null ? 0 : durationSeconds!.hashCode) +
    (state.hashCode) +
    (startedAt.hashCode) +
    (lastSeen.hashCode) +
    (encoder == null ? 0 : encoder!.hashCode) +
    (method == null ? 0 : method!.hashCode);

  @override
  String toString() => 'PlaybackSession[userId=$userId, deviceId=$deviceId, itemId=$itemId, positionSeconds=$positionSeconds, durationSeconds=$durationSeconds, state=$state, startedAt=$startedAt, lastSeen=$lastSeen, encoder=$encoder, method=$method]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'userId'] = this.userId;
      json[r'deviceId'] = this.deviceId;
      json[r'itemId'] = this.itemId;
      json[r'positionSeconds'] = this.positionSeconds;
    if (this.durationSeconds != null) {
      json[r'durationSeconds'] = this.durationSeconds;
    } else {
      json[r'durationSeconds'] = null;
    }
      json[r'state'] = this.state;
      json[r'startedAt'] = this.startedAt.toUtc().toIso8601String();
      json[r'lastSeen'] = this.lastSeen.toUtc().toIso8601String();
    if (this.encoder != null) {
      json[r'encoder'] = this.encoder;
    } else {
      json[r'encoder'] = null;
    }
    if (this.method != null) {
      json[r'method'] = this.method;
    } else {
      json[r'method'] = null;
    }
    return json;
  }

  /// Returns a new [PlaybackSession] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PlaybackSession? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'userId'), 'Required key "PlaybackSession[userId]" is missing from JSON.');
        assert(json[r'userId'] != null, 'Required key "PlaybackSession[userId]" has a null value in JSON.');
        assert(json.containsKey(r'deviceId'), 'Required key "PlaybackSession[deviceId]" is missing from JSON.');
        assert(json[r'deviceId'] != null, 'Required key "PlaybackSession[deviceId]" has a null value in JSON.');
        assert(json.containsKey(r'itemId'), 'Required key "PlaybackSession[itemId]" is missing from JSON.');
        assert(json[r'itemId'] != null, 'Required key "PlaybackSession[itemId]" has a null value in JSON.');
        assert(json.containsKey(r'positionSeconds'), 'Required key "PlaybackSession[positionSeconds]" is missing from JSON.');
        assert(json[r'positionSeconds'] != null, 'Required key "PlaybackSession[positionSeconds]" has a null value in JSON.');
        assert(json.containsKey(r'state'), 'Required key "PlaybackSession[state]" is missing from JSON.');
        assert(json[r'state'] != null, 'Required key "PlaybackSession[state]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'), 'Required key "PlaybackSession[startedAt]" is missing from JSON.');
        assert(json[r'startedAt'] != null, 'Required key "PlaybackSession[startedAt]" has a null value in JSON.');
        assert(json.containsKey(r'lastSeen'), 'Required key "PlaybackSession[lastSeen]" is missing from JSON.');
        assert(json[r'lastSeen'] != null, 'Required key "PlaybackSession[lastSeen]" has a null value in JSON.');
        return true;
      }());

      return PlaybackSession(
        userId: mapValueOfType<String>(json, r'userId')!,
        deviceId: mapValueOfType<String>(json, r'deviceId')!,
        itemId: mapValueOfType<String>(json, r'itemId')!,
        positionSeconds: mapValueOfType<double>(json, r'positionSeconds')!,
        durationSeconds: mapValueOfType<double>(json, r'durationSeconds'),
        state: mapValueOfType<String>(json, r'state')!,
        startedAt: mapDateTime(json, r'startedAt', r'')!,
        lastSeen: mapDateTime(json, r'lastSeen', r'')!,
        encoder: mapValueOfType<String>(json, r'encoder'),
        method: mapValueOfType<String>(json, r'method'),
      );
    }
    return null;
  }

  static List<PlaybackSession> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PlaybackSession>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PlaybackSession.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PlaybackSession> mapFromJson(dynamic json) {
    final map = <String, PlaybackSession>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PlaybackSession.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PlaybackSession-objects as value to a dart map
  static Map<String, List<PlaybackSession>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PlaybackSession>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PlaybackSession.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'userId',
    'deviceId',
    'itemId',
    'positionSeconds',
    'state',
    'startedAt',
    'lastSeen',
  };
}

