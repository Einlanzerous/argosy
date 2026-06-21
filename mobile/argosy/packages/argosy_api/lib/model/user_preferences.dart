//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UserPreferences {
  /// Returns a new [UserPreferences] instance.
  UserPreferences({
    required this.homeLayout,
  });

  /// Home density — focused trims to personal rows; discovery shows everything.
  UserPreferencesHomeLayoutEnum homeLayout;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UserPreferences &&
    other.homeLayout == homeLayout;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (homeLayout.hashCode);

  @override
  String toString() => 'UserPreferences[homeLayout=$homeLayout]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'homeLayout'] = this.homeLayout;
    return json;
  }

  /// Returns a new [UserPreferences] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UserPreferences? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'homeLayout'), 'Required key "UserPreferences[homeLayout]" is missing from JSON.');
        assert(json[r'homeLayout'] != null, 'Required key "UserPreferences[homeLayout]" has a null value in JSON.');
        return true;
      }());

      return UserPreferences(
        homeLayout: UserPreferencesHomeLayoutEnum.fromJson(json[r'homeLayout'])!,
      );
    }
    return null;
  }

  static List<UserPreferences> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UserPreferences>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserPreferences.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UserPreferences> mapFromJson(dynamic json) {
    final map = <String, UserPreferences>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UserPreferences.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UserPreferences-objects as value to a dart map
  static Map<String, List<UserPreferences>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UserPreferences>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UserPreferences.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'homeLayout',
  };
}

/// Home density — focused trims to personal rows; discovery shows everything.
class UserPreferencesHomeLayoutEnum {
  /// Instantiate a new enum with the provided [value].
  const UserPreferencesHomeLayoutEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const focused = UserPreferencesHomeLayoutEnum._(r'focused');
  static const discovery = UserPreferencesHomeLayoutEnum._(r'discovery');

  /// List of all possible values in this [enum][UserPreferencesHomeLayoutEnum].
  static const values = <UserPreferencesHomeLayoutEnum>[
    focused,
    discovery,
  ];

  static UserPreferencesHomeLayoutEnum? fromJson(dynamic value) => UserPreferencesHomeLayoutEnumTypeTransformer().decode(value);

  static List<UserPreferencesHomeLayoutEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UserPreferencesHomeLayoutEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserPreferencesHomeLayoutEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserPreferencesHomeLayoutEnum] to String,
/// and [decode] dynamic data back to [UserPreferencesHomeLayoutEnum].
class UserPreferencesHomeLayoutEnumTypeTransformer {
  factory UserPreferencesHomeLayoutEnumTypeTransformer() => _instance ??= const UserPreferencesHomeLayoutEnumTypeTransformer._();

  const UserPreferencesHomeLayoutEnumTypeTransformer._();

  String encode(UserPreferencesHomeLayoutEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UserPreferencesHomeLayoutEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserPreferencesHomeLayoutEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'focused': return UserPreferencesHomeLayoutEnum.focused;
        case r'discovery': return UserPreferencesHomeLayoutEnum.discovery;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UserPreferencesHomeLayoutEnumTypeTransformer] instance.
  static UserPreferencesHomeLayoutEnumTypeTransformer? _instance;
}


