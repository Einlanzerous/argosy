//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AddLabelRequest {
  /// Returns a new [AddLabelRequest] instance.
  AddLabelRequest({
    required this.label,
  });

  String label;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AddLabelRequest &&
    other.label == label;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (label.hashCode);

  @override
  String toString() => 'AddLabelRequest[label=$label]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'label'] = this.label;
    return json;
  }

  /// Returns a new [AddLabelRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AddLabelRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'label'), 'Required key "AddLabelRequest[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "AddLabelRequest[label]" has a null value in JSON.');
        return true;
      }());

      return AddLabelRequest(
        label: mapValueOfType<String>(json, r'label')!,
      );
    }
    return null;
  }

  static List<AddLabelRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AddLabelRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AddLabelRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AddLabelRequest> mapFromJson(dynamic json) {
    final map = <String, AddLabelRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AddLabelRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AddLabelRequest-objects as value to a dart map
  static Map<String, List<AddLabelRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AddLabelRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AddLabelRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'label',
  };
}

