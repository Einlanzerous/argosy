//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TranscodeStartRequest {
  /// Returns a new [TranscodeStartRequest] instance.
  TranscodeStartRequest({
    this.startAt,
    this.hevc,
    this.hevcHardware,
    this.burnInSubtitle,
  });

  /// Seek offset in seconds (default 0).
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? startAt;

  /// Whether the client can play HEVC (H.265) in fMP4/MSE — detected via MediaSource.isTypeSupported. When true, an HEVC source is remuxed (copied) at native resolution including 4K instead of being re-encoded to H.264 1080p, and re-encodes of >1080p sources target HEVC. Defaults to false (H.264 only). 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? hevc;

  /// MediaCapabilities.decodingInfo's view of whether this client decodes 10-bit HEVC (Main 10) in hardware — both `smooth` and `powerEfficient`. Read it asymmetrically: false is meaningful (the device has recorded decode stats and they are bad), while true is weak, because browsers report any supported configuration as smooth and powerEfficient until stats have been recorded on the device. The server treats it as a veto rather than a licence: a true only permits a 10-bit HEVC source to keep its bit depth and HDR above 1080p, where such a copy has been observed playing smoothly (ARGY-178). Absent or false re-encodes to 8-bit, which is the pre-ARGY-178 behaviour. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? hevcHardware;

  /// Id of an image-based subtitle track (a SubtitleTrack with burnIn true, e.g. \"burn:6\") to draw into the video frames. Image subtitles are bitmaps, so there is no WebVTT to hand a <track> element and the only way to show them is to paint them into the picture during the encode (ARGY-59). Doing so forces a full re-encode — the video stream can no longer be copied — and the result cannot be switched off without restarting the session, so send it only when the viewer picks such a track explicitly. Unset (the default) burns in nothing. An id that isn't an image subtitle stream of this item is a 400. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? burnInSubtitle;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TranscodeStartRequest &&
    other.startAt == startAt &&
    other.hevc == hevc &&
    other.hevcHardware == hevcHardware &&
    other.burnInSubtitle == burnInSubtitle;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (startAt == null ? 0 : startAt!.hashCode) +
    (hevc == null ? 0 : hevc!.hashCode) +
    (hevcHardware == null ? 0 : hevcHardware!.hashCode) +
    (burnInSubtitle == null ? 0 : burnInSubtitle!.hashCode);

  @override
  String toString() => 'TranscodeStartRequest[startAt=$startAt, hevc=$hevc, hevcHardware=$hevcHardware, burnInSubtitle=$burnInSubtitle]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.startAt != null) {
      json[r'startAt'] = this.startAt;
    } else {
      json[r'startAt'] = null;
    }
    if (this.hevc != null) {
      json[r'hevc'] = this.hevc;
    } else {
      json[r'hevc'] = null;
    }
    if (this.hevcHardware != null) {
      json[r'hevcHardware'] = this.hevcHardware;
    } else {
      json[r'hevcHardware'] = null;
    }
    if (this.burnInSubtitle != null) {
      json[r'burnInSubtitle'] = this.burnInSubtitle;
    } else {
      json[r'burnInSubtitle'] = null;
    }
    return json;
  }

  /// Returns a new [TranscodeStartRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TranscodeStartRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return TranscodeStartRequest(
        startAt: mapValueOfType<double>(json, r'startAt'),
        hevc: mapValueOfType<bool>(json, r'hevc'),
        hevcHardware: mapValueOfType<bool>(json, r'hevcHardware'),
        burnInSubtitle: mapValueOfType<String>(json, r'burnInSubtitle'),
      );
    }
    return null;
  }

  static List<TranscodeStartRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeStartRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeStartRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TranscodeStartRequest> mapFromJson(dynamic json) {
    final map = <String, TranscodeStartRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TranscodeStartRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TranscodeStartRequest-objects as value to a dart map
  static Map<String, List<TranscodeStartRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TranscodeStartRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TranscodeStartRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

