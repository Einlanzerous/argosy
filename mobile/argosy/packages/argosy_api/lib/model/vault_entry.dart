//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class VaultEntry {
  /// Returns a new [VaultEntry] instance.
  VaultEntry({
    required this.entryId,
    required this.kind,
    required this.id,
    required this.title,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.genres = const [],
  });

  /// The vault membership id (for remove/reorder).
  String entryId;

  VaultEntryKindEnum kind;

  /// The film or series id (for routing).
  String id;

  String title;

  int? year;

  String? posterUrl;

  String? backdropUrl;

  num? rating;

  /// Effective genres, for card captions. Omitted when none.
  List<String> genres;

  @override
  bool operator ==(Object other) => identical(this, other) || other is VaultEntry &&
    other.entryId == entryId &&
    other.kind == kind &&
    other.id == id &&
    other.title == title &&
    other.year == year &&
    other.posterUrl == posterUrl &&
    other.backdropUrl == backdropUrl &&
    other.rating == rating &&
    _deepEquality.equals(other.genres, genres);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (entryId.hashCode) +
    (kind.hashCode) +
    (id.hashCode) +
    (title.hashCode) +
    (year == null ? 0 : year!.hashCode) +
    (posterUrl == null ? 0 : posterUrl!.hashCode) +
    (backdropUrl == null ? 0 : backdropUrl!.hashCode) +
    (rating == null ? 0 : rating!.hashCode) +
    (genres.hashCode);

  @override
  String toString() => 'VaultEntry[entryId=$entryId, kind=$kind, id=$id, title=$title, year=$year, posterUrl=$posterUrl, backdropUrl=$backdropUrl, rating=$rating, genres=$genres]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'entryId'] = this.entryId;
      json[r'kind'] = this.kind;
      json[r'id'] = this.id;
      json[r'title'] = this.title;
    if (this.year != null) {
      json[r'year'] = this.year;
    } else {
      json[r'year'] = null;
    }
    if (this.posterUrl != null) {
      json[r'posterUrl'] = this.posterUrl;
    } else {
      json[r'posterUrl'] = null;
    }
    if (this.backdropUrl != null) {
      json[r'backdropUrl'] = this.backdropUrl;
    } else {
      json[r'backdropUrl'] = null;
    }
    if (this.rating != null) {
      json[r'rating'] = this.rating;
    } else {
      json[r'rating'] = null;
    }
      json[r'genres'] = this.genres;
    return json;
  }

  /// Returns a new [VaultEntry] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static VaultEntry? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'entryId'), 'Required key "VaultEntry[entryId]" is missing from JSON.');
        assert(json[r'entryId'] != null, 'Required key "VaultEntry[entryId]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "VaultEntry[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "VaultEntry[kind]" has a null value in JSON.');
        assert(json.containsKey(r'id'), 'Required key "VaultEntry[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "VaultEntry[id]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "VaultEntry[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "VaultEntry[title]" has a null value in JSON.');
        return true;
      }());

      return VaultEntry(
        entryId: mapValueOfType<String>(json, r'entryId')!,
        kind: VaultEntryKindEnum.fromJson(json[r'kind'])!,
        id: mapValueOfType<String>(json, r'id')!,
        title: mapValueOfType<String>(json, r'title')!,
        year: mapValueOfType<int>(json, r'year'),
        posterUrl: mapValueOfType<String>(json, r'posterUrl'),
        backdropUrl: mapValueOfType<String>(json, r'backdropUrl'),
        rating: json[r'rating'] == null
            ? null
            : num.parse('${json[r'rating']}'),
        genres: json[r'genres'] is Iterable
            ? (json[r'genres'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<VaultEntry> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <VaultEntry>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = VaultEntry.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, VaultEntry> mapFromJson(dynamic json) {
    final map = <String, VaultEntry>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = VaultEntry.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of VaultEntry-objects as value to a dart map
  static Map<String, List<VaultEntry>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<VaultEntry>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = VaultEntry.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'entryId',
    'kind',
    'id',
    'title',
  };
}


class VaultEntryKindEnum {
  /// Instantiate a new enum with the provided [value].
  const VaultEntryKindEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const movie = VaultEntryKindEnum._(r'movie');
  static const series = VaultEntryKindEnum._(r'series');

  /// List of all possible values in this [enum][VaultEntryKindEnum].
  static const values = <VaultEntryKindEnum>[
    movie,
    series,
  ];

  static VaultEntryKindEnum? fromJson(dynamic value) => VaultEntryKindEnumTypeTransformer().decode(value);

  static List<VaultEntryKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <VaultEntryKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = VaultEntryKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [VaultEntryKindEnum] to String,
/// and [decode] dynamic data back to [VaultEntryKindEnum].
class VaultEntryKindEnumTypeTransformer {
  factory VaultEntryKindEnumTypeTransformer() => _instance ??= const VaultEntryKindEnumTypeTransformer._();

  const VaultEntryKindEnumTypeTransformer._();

  String encode(VaultEntryKindEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a VaultEntryKindEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  VaultEntryKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'movie': return VaultEntryKindEnum.movie;
        case r'series': return VaultEntryKindEnum.series;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [VaultEntryKindEnumTypeTransformer] instance.
  static VaultEntryKindEnumTypeTransformer? _instance;
}


