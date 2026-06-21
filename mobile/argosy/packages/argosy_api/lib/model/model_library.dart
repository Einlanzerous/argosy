//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ModelLibrary {
  /// Returns a new [ModelLibrary] instance.
  ModelLibrary({
    required this.id,
    required this.name,
    required this.kind,
    this.rootPath,
  });

  String id;

  String name;

  String kind;

  /// Server-side media root (admin only).
  String? rootPath;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ModelLibrary &&
    other.id == id &&
    other.name == name &&
    other.kind == kind &&
    other.rootPath == rootPath;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (kind.hashCode) +
    (rootPath == null ? 0 : rootPath!.hashCode);

  @override
  String toString() => 'ModelLibrary[id=$id, name=$name, kind=$kind, rootPath=$rootPath]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
      json[r'kind'] = this.kind;
    if (this.rootPath != null) {
      json[r'rootPath'] = this.rootPath;
    } else {
      json[r'rootPath'] = null;
    }
    return json;
  }

  /// Returns a new [ModelLibrary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ModelLibrary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "ModelLibrary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "ModelLibrary[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "ModelLibrary[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ModelLibrary[name]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "ModelLibrary[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "ModelLibrary[kind]" has a null value in JSON.');
        return true;
      }());

      return ModelLibrary(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        kind: mapValueOfType<String>(json, r'kind')!,
        rootPath: mapValueOfType<String>(json, r'rootPath'),
      );
    }
    return null;
  }

  static List<ModelLibrary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ModelLibrary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ModelLibrary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ModelLibrary> mapFromJson(dynamic json) {
    final map = <String, ModelLibrary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ModelLibrary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ModelLibrary-objects as value to a dart map
  static Map<String, List<ModelLibrary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ModelLibrary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ModelLibrary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
    'kind',
  };
}

