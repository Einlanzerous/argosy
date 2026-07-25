//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountLookupResponse {
  /// Returns a new [AccountLookupResponse] instance.
  AccountLookupResponse({
    required this.account,
  });

  Account account;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountLookupResponse &&
    other.account == account;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (account.hashCode);

  @override
  String toString() => 'AccountLookupResponse[account=$account]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'account'] = this.account;
    return json;
  }

  /// Returns a new [AccountLookupResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AccountLookupResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'account'), 'Required key "AccountLookupResponse[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "AccountLookupResponse[account]" has a null value in JSON.');
        return true;
      }());

      return AccountLookupResponse(
        account: Account.fromJson(json[r'account'])!,
      );
    }
    return null;
  }

  static List<AccountLookupResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountLookupResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountLookupResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountLookupResponse> mapFromJson(dynamic json) {
    final map = <String, AccountLookupResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountLookupResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AccountLookupResponse-objects as value to a dart map
  static Map<String, List<AccountLookupResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountLookupResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountLookupResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'account',
  };
}

