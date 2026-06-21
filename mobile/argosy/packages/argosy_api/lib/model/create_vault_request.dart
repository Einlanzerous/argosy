//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateVaultRequest {
  /// Returns a new [CreateVaultRequest] instance.
  CreateVaultRequest({
    required this.name,
    this.description,
    this.shared = false,
  });

  String name;

  String? description;

  bool shared;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateVaultRequest &&
    other.name == name &&
    other.description == description &&
    other.shared == shared;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (shared.hashCode);

  @override
  String toString() => 'CreateVaultRequest[name=$name, description=$description, shared=$shared]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
      json[r'shared'] = this.shared;
    return json;
  }

  /// Returns a new [CreateVaultRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CreateVaultRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'name'), 'Required key "CreateVaultRequest[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "CreateVaultRequest[name]" has a null value in JSON.');
        return true;
      }());

      return CreateVaultRequest(
        name: mapValueOfType<String>(json, r'name')!,
        description: mapValueOfType<String>(json, r'description'),
        shared: mapValueOfType<bool>(json, r'shared') ?? false,
      );
    }
    return null;
  }

  static List<CreateVaultRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateVaultRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateVaultRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateVaultRequest> mapFromJson(dynamic json) {
    final map = <String, CreateVaultRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateVaultRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CreateVaultRequest-objects as value to a dart map
  static Map<String, List<CreateVaultRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateVaultRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateVaultRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'name',
  };
}

