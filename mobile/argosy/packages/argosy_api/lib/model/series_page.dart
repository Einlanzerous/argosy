//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SeriesPage {
  /// Returns a new [SeriesPage] instance.
  SeriesPage({
    this.items = const [],
    required this.total,
    required this.limit,
    required this.offset,
  });

  List<SeriesSummary> items;

  int total;

  int limit;

  int offset;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SeriesPage &&
    _deepEquality.equals(other.items, items) &&
    other.total == total &&
    other.limit == limit &&
    other.offset == offset;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total.hashCode) +
    (limit.hashCode) +
    (offset.hashCode);

  @override
  String toString() => 'SeriesPage[items=$items, total=$total, limit=$limit, offset=$offset]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
      json[r'limit'] = this.limit;
      json[r'offset'] = this.offset;
    return json;
  }

  /// Returns a new [SeriesPage] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SeriesPage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'items'), 'Required key "SeriesPage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "SeriesPage[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "SeriesPage[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "SeriesPage[total]" has a null value in JSON.');
        assert(json.containsKey(r'limit'), 'Required key "SeriesPage[limit]" is missing from JSON.');
        assert(json[r'limit'] != null, 'Required key "SeriesPage[limit]" has a null value in JSON.');
        assert(json.containsKey(r'offset'), 'Required key "SeriesPage[offset]" is missing from JSON.');
        assert(json[r'offset'] != null, 'Required key "SeriesPage[offset]" has a null value in JSON.');
        return true;
      }());

      return SeriesPage(
        items: SeriesSummary.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
        limit: mapValueOfType<int>(json, r'limit')!,
        offset: mapValueOfType<int>(json, r'offset')!,
      );
    }
    return null;
  }

  static List<SeriesPage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SeriesPage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SeriesPage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SeriesPage> mapFromJson(dynamic json) {
    final map = <String, SeriesPage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SeriesPage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SeriesPage-objects as value to a dart map
  static Map<String, List<SeriesPage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SeriesPage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SeriesPage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'items',
    'total',
    'limit',
    'offset',
  };
}

