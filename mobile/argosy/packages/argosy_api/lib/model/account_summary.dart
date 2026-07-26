//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountSummary {
  /// Returns a new [AccountSummary] instance.
  AccountSummary({
    required this.id,
    required this.email,
    required this.name,
    required this.isOwner,
    required this.disabled,
    required this.profileCount,
    required this.createdAt,
  });

  String id;

  String email;

  String name;

  /// Whether this account owns the instance (ARGY-167).
  bool isOwner;

  /// Disabled accounts can't sign in and their devices stop authenticating.
  bool disabled;

  int profileCount;

  DateTime createdAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountSummary &&
    other.id == id &&
    other.email == email &&
    other.name == name &&
    other.isOwner == isOwner &&
    other.disabled == disabled &&
    other.profileCount == profileCount &&
    other.createdAt == createdAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (email.hashCode) +
    (name.hashCode) +
    (isOwner.hashCode) +
    (disabled.hashCode) +
    (profileCount.hashCode) +
    (createdAt.hashCode);

  @override
  String toString() => 'AccountSummary[id=$id, email=$email, name=$name, isOwner=$isOwner, disabled=$disabled, profileCount=$profileCount, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'email'] = this.email;
      json[r'name'] = this.name;
      json[r'isOwner'] = this.isOwner;
      json[r'disabled'] = this.disabled;
      json[r'profileCount'] = this.profileCount;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [AccountSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AccountSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "AccountSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "AccountSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "AccountSummary[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "AccountSummary[email]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "AccountSummary[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "AccountSummary[name]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "AccountSummary[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "AccountSummary[isOwner]" has a null value in JSON.');
        assert(json.containsKey(r'disabled'), 'Required key "AccountSummary[disabled]" is missing from JSON.');
        assert(json[r'disabled'] != null, 'Required key "AccountSummary[disabled]" has a null value in JSON.');
        assert(json.containsKey(r'profileCount'), 'Required key "AccountSummary[profileCount]" is missing from JSON.');
        assert(json[r'profileCount'] != null, 'Required key "AccountSummary[profileCount]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "AccountSummary[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "AccountSummary[createdAt]" has a null value in JSON.');
        return true;
      }());

      return AccountSummary(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        name: mapValueOfType<String>(json, r'name')!,
        isOwner: mapValueOfType<bool>(json, r'isOwner')!,
        disabled: mapValueOfType<bool>(json, r'disabled')!,
        profileCount: mapValueOfType<int>(json, r'profileCount')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<AccountSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountSummary> mapFromJson(dynamic json) {
    final map = <String, AccountSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AccountSummary-objects as value to a dart map
  static Map<String, List<AccountSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'email',
    'name',
    'isOwner',
    'disabled',
    'profileCount',
    'createdAt',
  };
}

