//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class VaultDetail {
  /// Returns a new [VaultDetail] instance.
  VaultDetail({
    required this.id,
    required this.name,
    this.description,
    required this.shared,
    required this.ownerId,
    required this.ownerName,
    required this.itemCount,
    required this.isOwner,
    required this.canEdit,
    this.items = const [],
  });

  String id;

  String name;

  String? description;

  bool shared;

  String ownerId;

  String ownerName;

  int itemCount;

  bool isOwner;

  /// Whether the calling profile may add/remove/reorder items.
  bool canEdit;

  List<VaultEntry> items;

  @override
  bool operator ==(Object other) => identical(this, other) || other is VaultDetail &&
    other.id == id &&
    other.name == name &&
    other.description == description &&
    other.shared == shared &&
    other.ownerId == ownerId &&
    other.ownerName == ownerName &&
    other.itemCount == itemCount &&
    other.isOwner == isOwner &&
    other.canEdit == canEdit &&
    _deepEquality.equals(other.items, items);

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
    (isOwner.hashCode) +
    (canEdit.hashCode) +
    (items.hashCode);

  @override
  String toString() => 'VaultDetail[id=$id, name=$name, description=$description, shared=$shared, ownerId=$ownerId, ownerName=$ownerName, itemCount=$itemCount, isOwner=$isOwner, canEdit=$canEdit, items=$items]';

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
      json[r'canEdit'] = this.canEdit;
      json[r'items'] = this.items;
    return json;
  }

  /// Returns a new [VaultDetail] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static VaultDetail? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "VaultDetail[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "VaultDetail[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "VaultDetail[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "VaultDetail[name]" has a null value in JSON.');
        assert(json.containsKey(r'shared'), 'Required key "VaultDetail[shared]" is missing from JSON.');
        assert(json[r'shared'] != null, 'Required key "VaultDetail[shared]" has a null value in JSON.');
        assert(json.containsKey(r'ownerId'), 'Required key "VaultDetail[ownerId]" is missing from JSON.');
        assert(json[r'ownerId'] != null, 'Required key "VaultDetail[ownerId]" has a null value in JSON.');
        assert(json.containsKey(r'ownerName'), 'Required key "VaultDetail[ownerName]" is missing from JSON.');
        assert(json[r'ownerName'] != null, 'Required key "VaultDetail[ownerName]" has a null value in JSON.');
        assert(json.containsKey(r'itemCount'), 'Required key "VaultDetail[itemCount]" is missing from JSON.');
        assert(json[r'itemCount'] != null, 'Required key "VaultDetail[itemCount]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "VaultDetail[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "VaultDetail[isOwner]" has a null value in JSON.');
        assert(json.containsKey(r'canEdit'), 'Required key "VaultDetail[canEdit]" is missing from JSON.');
        assert(json[r'canEdit'] != null, 'Required key "VaultDetail[canEdit]" has a null value in JSON.');
        assert(json.containsKey(r'items'), 'Required key "VaultDetail[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "VaultDetail[items]" has a null value in JSON.');
        return true;
      }());

      return VaultDetail(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
        description: mapValueOfType<String>(json, r'description'),
        shared: mapValueOfType<bool>(json, r'shared')!,
        ownerId: mapValueOfType<String>(json, r'ownerId')!,
        ownerName: mapValueOfType<String>(json, r'ownerName')!,
        itemCount: mapValueOfType<int>(json, r'itemCount')!,
        isOwner: mapValueOfType<bool>(json, r'isOwner')!,
        canEdit: mapValueOfType<bool>(json, r'canEdit')!,
        items: VaultEntry.listFromJson(json[r'items']),
      );
    }
    return null;
  }

  static List<VaultDetail> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <VaultDetail>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = VaultDetail.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, VaultDetail> mapFromJson(dynamic json) {
    final map = <String, VaultDetail>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = VaultDetail.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of VaultDetail-objects as value to a dart map
  static Map<String, List<VaultDetail>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<VaultDetail>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = VaultDetail.listFromJson(entry.value, growable: growable,);
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
    'canEdit',
    'items',
  };
}

