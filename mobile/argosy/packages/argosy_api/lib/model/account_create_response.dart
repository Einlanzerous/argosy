//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountCreateResponse {
  /// Returns a new [AccountCreateResponse] instance.
  AccountCreateResponse({
    required this.account,
    this.generatedPassword,
  });

  Account account;

  /// Present only when the request omitted `password`. Delivered exactly once — Argosy stores only the bcrypt hash.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? generatedPassword;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountCreateResponse &&
    other.account == account &&
    other.generatedPassword == generatedPassword;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (account.hashCode) +
    (generatedPassword == null ? 0 : generatedPassword!.hashCode);

  @override
  String toString() => 'AccountCreateResponse[account=$account, generatedPassword=$generatedPassword]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'account'] = this.account;
    if (this.generatedPassword != null) {
      json[r'generatedPassword'] = this.generatedPassword;
    } else {
      json[r'generatedPassword'] = null;
    }
    return json;
  }

  /// Returns a new [AccountCreateResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AccountCreateResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'account'), 'Required key "AccountCreateResponse[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "AccountCreateResponse[account]" has a null value in JSON.');
        return true;
      }());

      return AccountCreateResponse(
        account: Account.fromJson(json[r'account'])!,
        generatedPassword: mapValueOfType<String>(json, r'generatedPassword'),
      );
    }
    return null;
  }

  static List<AccountCreateResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountCreateResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountCreateResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountCreateResponse> mapFromJson(dynamic json) {
    final map = <String, AccountCreateResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountCreateResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AccountCreateResponse-objects as value to a dart map
  static Map<String, List<AccountCreateResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountCreateResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountCreateResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'account',
  };
}

