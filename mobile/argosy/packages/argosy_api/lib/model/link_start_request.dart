//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class LinkStartRequest {
  /// Returns a new [LinkStartRequest] instance.
  LinkStartRequest({
    this.deviceName,
    this.platform,
  });

  /// The new device's suggested Fleet name (e.g. \"Pixel 9\"). The approver may override it.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? deviceName;

  /// The new device's platform (android, ios, androidtv, web). Defaults to androidtv for older clients that send no body.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? platform;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LinkStartRequest &&
    other.deviceName == deviceName &&
    other.platform == platform;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (deviceName == null ? 0 : deviceName!.hashCode) +
    (platform == null ? 0 : platform!.hashCode);

  @override
  String toString() => 'LinkStartRequest[deviceName=$deviceName, platform=$platform]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.deviceName != null) {
      json[r'deviceName'] = this.deviceName;
    } else {
      json[r'deviceName'] = null;
    }
    if (this.platform != null) {
      json[r'platform'] = this.platform;
    } else {
      json[r'platform'] = null;
    }
    return json;
  }

  /// Returns a new [LinkStartRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static LinkStartRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return LinkStartRequest(
        deviceName: mapValueOfType<String>(json, r'deviceName'),
        platform: mapValueOfType<String>(json, r'platform'),
      );
    }
    return null;
  }

  static List<LinkStartRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LinkStartRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LinkStartRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, LinkStartRequest> mapFromJson(dynamic json) {
    final map = <String, LinkStartRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = LinkStartRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of LinkStartRequest-objects as value to a dart map
  static Map<String, List<LinkStartRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<LinkStartRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = LinkStartRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

