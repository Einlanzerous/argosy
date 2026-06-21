//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateLibraryRequest {
  /// Returns a new [CreateLibraryRequest] instance.
  CreateLibraryRequest({
    required this.name,
    required this.path,
    this.kind = const CreateLibraryRequestKindEnum._('mixed'),
  });

  String name;

  /// Absolute path on the server; must be an existing directory.
  String path;

  CreateLibraryRequestKindEnum kind;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateLibraryRequest &&
    other.name == name &&
    other.path == path &&
    other.kind == kind;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (path.hashCode) +
    (kind.hashCode);

  @override
  String toString() => 'CreateLibraryRequest[name=$name, path=$path, kind=$kind]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
      json[r'path'] = this.path;
      json[r'kind'] = this.kind;
    return json;
  }

  /// Returns a new [CreateLibraryRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CreateLibraryRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'name'), 'Required key "CreateLibraryRequest[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "CreateLibraryRequest[name]" has a null value in JSON.');
        assert(json.containsKey(r'path'), 'Required key "CreateLibraryRequest[path]" is missing from JSON.');
        assert(json[r'path'] != null, 'Required key "CreateLibraryRequest[path]" has a null value in JSON.');
        return true;
      }());

      return CreateLibraryRequest(
        name: mapValueOfType<String>(json, r'name')!,
        path: mapValueOfType<String>(json, r'path')!,
        kind: CreateLibraryRequestKindEnum.fromJson(json[r'kind']) ?? const CreateLibraryRequestKindEnum._('mixed'),
      );
    }
    return null;
  }

  static List<CreateLibraryRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateLibraryRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateLibraryRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateLibraryRequest> mapFromJson(dynamic json) {
    final map = <String, CreateLibraryRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateLibraryRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CreateLibraryRequest-objects as value to a dart map
  static Map<String, List<CreateLibraryRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateLibraryRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateLibraryRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'name',
    'path',
  };
}


class CreateLibraryRequestKindEnum {
  /// Instantiate a new enum with the provided [value].
  const CreateLibraryRequestKindEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const movie = CreateLibraryRequestKindEnum._(r'movie');
  static const show_ = CreateLibraryRequestKindEnum._(r'show');
  static const mixed = CreateLibraryRequestKindEnum._(r'mixed');

  /// List of all possible values in this [enum][CreateLibraryRequestKindEnum].
  static const values = <CreateLibraryRequestKindEnum>[
    movie,
    show_,
    mixed,
  ];

  static CreateLibraryRequestKindEnum? fromJson(dynamic value) => CreateLibraryRequestKindEnumTypeTransformer().decode(value);

  static List<CreateLibraryRequestKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateLibraryRequestKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateLibraryRequestKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CreateLibraryRequestKindEnum] to String,
/// and [decode] dynamic data back to [CreateLibraryRequestKindEnum].
class CreateLibraryRequestKindEnumTypeTransformer {
  factory CreateLibraryRequestKindEnumTypeTransformer() => _instance ??= const CreateLibraryRequestKindEnumTypeTransformer._();

  const CreateLibraryRequestKindEnumTypeTransformer._();

  String encode(CreateLibraryRequestKindEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a CreateLibraryRequestKindEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CreateLibraryRequestKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'movie': return CreateLibraryRequestKindEnum.movie;
        case r'show': return CreateLibraryRequestKindEnum.show_;
        case r'mixed': return CreateLibraryRequestKindEnum.mixed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [CreateLibraryRequestKindEnumTypeTransformer] instance.
  static CreateLibraryRequestKindEnumTypeTransformer? _instance;
}


