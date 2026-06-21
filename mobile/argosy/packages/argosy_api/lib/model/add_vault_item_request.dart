//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AddVaultItemRequest {
  /// Returns a new [AddVaultItemRequest] instance.
  AddVaultItemRequest({
    this.movieId,
    this.seriesId,
  });

  String? movieId;

  String? seriesId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AddVaultItemRequest &&
    other.movieId == movieId &&
    other.seriesId == seriesId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (movieId == null ? 0 : movieId!.hashCode) +
    (seriesId == null ? 0 : seriesId!.hashCode);

  @override
  String toString() => 'AddVaultItemRequest[movieId=$movieId, seriesId=$seriesId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.movieId != null) {
      json[r'movieId'] = this.movieId;
    } else {
      json[r'movieId'] = null;
    }
    if (this.seriesId != null) {
      json[r'seriesId'] = this.seriesId;
    } else {
      json[r'seriesId'] = null;
    }
    return json;
  }

  /// Returns a new [AddVaultItemRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AddVaultItemRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return AddVaultItemRequest(
        movieId: mapValueOfType<String>(json, r'movieId'),
        seriesId: mapValueOfType<String>(json, r'seriesId'),
      );
    }
    return null;
  }

  static List<AddVaultItemRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AddVaultItemRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AddVaultItemRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AddVaultItemRequest> mapFromJson(dynamic json) {
    final map = <String, AddVaultItemRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AddVaultItemRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AddVaultItemRequest-objects as value to a dart map
  static Map<String, List<AddVaultItemRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AddVaultItemRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AddVaultItemRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

