//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Facet {
  /// Returns a new [Facet] instance.
  Facet({
    required this.type,
    required this.value,
    required this.count,
  });

  /// Which dimension the value belongs to.
  FacetTypeEnum type;

  String value;

  /// Number of films + series carrying it.
  int count;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Facet &&
    other.type == type &&
    other.value == value &&
    other.count == count;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (type.hashCode) +
    (value.hashCode) +
    (count.hashCode);

  @override
  String toString() => 'Facet[type=$type, value=$value, count=$count]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'value'] = this.value;
      json[r'count'] = this.count;
    return json;
  }

  /// Returns a new [Facet] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Facet? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'type'), 'Required key "Facet[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "Facet[type]" has a null value in JSON.');
        assert(json.containsKey(r'value'), 'Required key "Facet[value]" is missing from JSON.');
        assert(json[r'value'] != null, 'Required key "Facet[value]" has a null value in JSON.');
        assert(json.containsKey(r'count'), 'Required key "Facet[count]" is missing from JSON.');
        assert(json[r'count'] != null, 'Required key "Facet[count]" has a null value in JSON.');
        return true;
      }());

      return Facet(
        type: FacetTypeEnum.fromJson(json[r'type'])!,
        value: mapValueOfType<String>(json, r'value')!,
        count: mapValueOfType<int>(json, r'count')!,
      );
    }
    return null;
  }

  static List<Facet> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Facet>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Facet.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Facet> mapFromJson(dynamic json) {
    final map = <String, Facet>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Facet.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Facet-objects as value to a dart map
  static Map<String, List<Facet>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Facet>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Facet.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'type',
    'value',
    'count',
  };
}

/// Which dimension the value belongs to.
class FacetTypeEnum {
  /// Instantiate a new enum with the provided [value].
  const FacetTypeEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const genre = FacetTypeEnum._(r'genre');
  static const tag = FacetTypeEnum._(r'tag');

  /// List of all possible values in this [enum][FacetTypeEnum].
  static const values = <FacetTypeEnum>[
    genre,
    tag,
  ];

  static FacetTypeEnum? fromJson(dynamic value) => FacetTypeEnumTypeTransformer().decode(value);

  static List<FacetTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <FacetTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = FacetTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [FacetTypeEnum] to String,
/// and [decode] dynamic data back to [FacetTypeEnum].
class FacetTypeEnumTypeTransformer {
  factory FacetTypeEnumTypeTransformer() => _instance ??= const FacetTypeEnumTypeTransformer._();

  const FacetTypeEnumTypeTransformer._();

  String encode(FacetTypeEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a FacetTypeEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  FacetTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'genre': return FacetTypeEnum.genre;
        case r'tag': return FacetTypeEnum.tag;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [FacetTypeEnumTypeTransformer] instance.
  static FacetTypeEnumTypeTransformer? _instance;
}


