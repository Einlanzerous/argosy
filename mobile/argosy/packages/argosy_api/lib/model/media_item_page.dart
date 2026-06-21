//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class MediaItemPage {
  /// Returns a new [MediaItemPage] instance.
  MediaItemPage({
    this.items = const [],
    required this.total,
    required this.limit,
    required this.offset,
  });

  List<MediaItemSummary> items;

  int total;

  int limit;

  int offset;

  @override
  bool operator ==(Object other) => identical(this, other) || other is MediaItemPage &&
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
  String toString() => 'MediaItemPage[items=$items, total=$total, limit=$limit, offset=$offset]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
      json[r'limit'] = this.limit;
      json[r'offset'] = this.offset;
    return json;
  }

  /// Returns a new [MediaItemPage] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MediaItemPage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'items'), 'Required key "MediaItemPage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "MediaItemPage[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "MediaItemPage[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "MediaItemPage[total]" has a null value in JSON.');
        assert(json.containsKey(r'limit'), 'Required key "MediaItemPage[limit]" is missing from JSON.');
        assert(json[r'limit'] != null, 'Required key "MediaItemPage[limit]" has a null value in JSON.');
        assert(json.containsKey(r'offset'), 'Required key "MediaItemPage[offset]" is missing from JSON.');
        assert(json[r'offset'] != null, 'Required key "MediaItemPage[offset]" has a null value in JSON.');
        return true;
      }());

      return MediaItemPage(
        items: MediaItemSummary.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
        limit: mapValueOfType<int>(json, r'limit')!,
        offset: mapValueOfType<int>(json, r'offset')!,
      );
    }
    return null;
  }

  static List<MediaItemPage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <MediaItemPage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MediaItemPage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MediaItemPage> mapFromJson(dynamic json) {
    final map = <String, MediaItemPage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MediaItemPage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MediaItemPage-objects as value to a dart map
  static Map<String, List<MediaItemPage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<MediaItemPage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MediaItemPage.listFromJson(entry.value, growable: growable,);
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

