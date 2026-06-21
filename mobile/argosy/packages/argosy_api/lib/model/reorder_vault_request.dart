//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ReorderVaultRequest {
  /// Returns a new [ReorderVaultRequest] instance.
  ReorderVaultRequest({
    this.entryIds = const [],
  });

  /// Entry ids in the desired order.
  List<String> entryIds;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ReorderVaultRequest &&
    _deepEquality.equals(other.entryIds, entryIds);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (entryIds.hashCode);

  @override
  String toString() => 'ReorderVaultRequest[entryIds=$entryIds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'entryIds'] = this.entryIds;
    return json;
  }

  /// Returns a new [ReorderVaultRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ReorderVaultRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'entryIds'), 'Required key "ReorderVaultRequest[entryIds]" is missing from JSON.');
        assert(json[r'entryIds'] != null, 'Required key "ReorderVaultRequest[entryIds]" has a null value in JSON.');
        return true;
      }());

      return ReorderVaultRequest(
        entryIds: json[r'entryIds'] is Iterable
            ? (json[r'entryIds'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<ReorderVaultRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ReorderVaultRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReorderVaultRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ReorderVaultRequest> mapFromJson(dynamic json) {
    final map = <String, ReorderVaultRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ReorderVaultRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ReorderVaultRequest-objects as value to a dart map
  static Map<String, List<ReorderVaultRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ReorderVaultRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ReorderVaultRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'entryIds',
  };
}

