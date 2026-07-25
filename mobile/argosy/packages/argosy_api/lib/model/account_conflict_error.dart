//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountConflictError {
  /// Returns a new [AccountConflictError] instance.
  AccountConflictError({
    required this.error,
    required this.account,
  });

  String error;

  Account account;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountConflictError &&
    other.error == error &&
    other.account == account;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (error.hashCode) +
    (account.hashCode);

  @override
  String toString() => 'AccountConflictError[error=$error, account=$account]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'error'] = this.error;
      json[r'account'] = this.account;
    return json;
  }

  /// Returns a new [AccountConflictError] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AccountConflictError? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'error'), 'Required key "AccountConflictError[error]" is missing from JSON.');
        assert(json[r'error'] != null, 'Required key "AccountConflictError[error]" has a null value in JSON.');
        assert(json.containsKey(r'account'), 'Required key "AccountConflictError[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "AccountConflictError[account]" has a null value in JSON.');
        return true;
      }());

      return AccountConflictError(
        error: mapValueOfType<String>(json, r'error')!,
        account: Account.fromJson(json[r'account'])!,
      );
    }
    return null;
  }

  static List<AccountConflictError> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountConflictError>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountConflictError.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountConflictError> mapFromJson(dynamic json) {
    final map = <String, AccountConflictError>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountConflictError.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AccountConflictError-objects as value to a dart map
  static Map<String, List<AccountConflictError>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountConflictError>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountConflictError.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'error',
    'account',
  };
}

