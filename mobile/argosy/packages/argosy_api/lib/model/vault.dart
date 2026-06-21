//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Vault {
  /// Returns a new [Vault] instance.
  Vault({
    required this.id,
    required this.name,
    this.description,
    required this.shared,
    required this.ownerId,
    required this.ownerName,
    required this.itemCount,
    required this.isOwner,
  });

  String id;

  String name;

  String? description;

  /// Visible to and curatable by the whole household.
  bool shared;

  String ownerId;

  String ownerName;

  int itemCount;

  /// Whether the calling profile owns this vault.
  bool isOwner;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Vault &&
    other.id == id &&
    other.name == name &&
    other.description == description &&
    other.shared == shared &&
    other.ownerId == ownerId &&
    other.ownerName == ownerName &&
    other.itemCount == itemCount &&
    other.isOwner == isOwner;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (shared.hashCode) +
    (ownerId.hashCode) +
    (ownerName.hashCode) +
    (itemCount.hashCode) +
    (isOwner.hashCode);

  @override
  String toString() => 'Vault[id=$id, name=$name, description=$description, shared=$shared, ownerId=$ownerId, ownerName=$ownerName, itemCount=$itemCount, isOwner=$isOwner]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
      json[r'shared'] = this.shared;
      json[r'ownerId'] = this.ownerId;
      json[r'ownerName'] = this.ownerName;
      json[r'itemCount'] = this.itemCount;
      json[r'isOwner'] = this.isOwner;
    return json;
  }

  /// Returns a new [Vault] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Vault? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Vault[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Vault[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "Vault[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "Vault[name]" has a null value in JSON.');
        assert(json.containsKey(r'shared'), 'Required key "Vault[shared]" is missing from JSON.');
        assert(json[r'shared'] != null, 'Required key "Vault[shared]" has a null value in JSON.');
        assert(json.containsKey(r'ownerId'), 'Required key "Vault[ownerId]" is missing from JSON.');
        assert(json[r'ownerId'] != null, 'Required key "Vault[ownerId]" has a null value in JSON.');
        assert(json.containsKey(r'ownerName'), 'Required key "Vault[ownerName]" is missing from JSON.');
        assert(json[r'ownerName'] != null, 'Required key "Vault[ownerName]" has a null value in JSON.');
        assert(json.containsKey(r'itemCount'), 'Required key "Vault[itemCount]" is missing from JSON.');
        assert(json[r'itemCount'] != null, 'Required key "Vault[itemCount]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "Vault[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "Vault[isOwner]" has a null value in JSON.');
        return true;
      }());

      return Vault(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        description: mapValueOfType<String>(json, r'description'),
        shared: mapValueOfType<bool>(json, r'shared')!,
        ownerId: mapValueOfType<String>(json, r'ownerId')!,
        ownerName: mapValueOfType<String>(json, r'ownerName')!,
        itemCount: mapValueOfType<int>(json, r'itemCount')!,
        isOwner: mapValueOfType<bool>(json, r'isOwner')!,
      );
    }
    return null;
  }

  static List<Vault> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Vault>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Vault.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Vault> mapFromJson(dynamic json) {
    final map = <String, Vault>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Vault.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Vault-objects as value to a dart map
  static Map<String, List<Vault>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Vault>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Vault.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'name',
    'shared',
    'ownerId',
    'ownerName',
    'itemCount',
    'isOwner',
  };
}

