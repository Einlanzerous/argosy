//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class LinkApproveRequest {
  /// Returns a new [LinkApproveRequest] instance.
  LinkApproveRequest({
    this.deviceName,
  });

  /// Friendly name for the TV in the Fleet (defaults to \"Living Room TV\").
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? deviceName;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LinkApproveRequest &&
    other.deviceName == deviceName;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (deviceName == null ? 0 : deviceName!.hashCode);

  @override
  String toString() => 'LinkApproveRequest[deviceName=$deviceName]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.deviceName != null) {
      json[r'deviceName'] = this.deviceName;
    } else {
      json[r'deviceName'] = null;
    }
    return json;
  }

  /// Returns a new [LinkApproveRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static LinkApproveRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return LinkApproveRequest(
        deviceName: mapValueOfType<String>(json, r'deviceName'),
      );
    }
    return null;
  }

  static List<LinkApproveRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LinkApproveRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LinkApproveRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, LinkApproveRequest> mapFromJson(dynamic json) {
    final map = <String, LinkApproveRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = LinkApproveRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of LinkApproveRequest-objects as value to a dart map
  static Map<String, List<LinkApproveRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<LinkApproveRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = LinkApproveRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

