//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class LinkStatusResponse {
  /// Returns a new [LinkStatusResponse] instance.
  LinkStatusResponse({
    required this.status,
    this.token,
  });

  LinkStatusResponseStatusEnum status;

  /// The device bearer token, present once the code is approved. Returned exactly once — the code is consumed on the poll that returns it.
  String? token;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LinkStatusResponse &&
    other.status == status &&
    other.token == token;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status.hashCode) +
    (token == null ? 0 : token!.hashCode);

  @override
  String toString() => 'LinkStatusResponse[status=$status, token=$token]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'status'] = this.status;
    if (this.token != null) {
      json[r'token'] = this.token;
    } else {
      json[r'token'] = null;
    }
    return json;
  }

  /// Returns a new [LinkStatusResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static LinkStatusResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'), 'Required key "LinkStatusResponse[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "LinkStatusResponse[status]" has a null value in JSON.');
        return true;
      }());

      return LinkStatusResponse(
        status: LinkStatusResponseStatusEnum.fromJson(json[r'status'])!,
        token: mapValueOfType<String>(json, r'token'),
      );
    }
    return null;
  }

  static List<LinkStatusResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LinkStatusResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LinkStatusResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, LinkStatusResponse> mapFromJson(dynamic json) {
    final map = <String, LinkStatusResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = LinkStatusResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of LinkStatusResponse-objects as value to a dart map
  static Map<String, List<LinkStatusResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<LinkStatusResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = LinkStatusResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'status',
  };
}


class LinkStatusResponseStatusEnum {
  /// Instantiate a new enum with the provided [value].
  const LinkStatusResponseStatusEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const pending = LinkStatusResponseStatusEnum._(r'pending');
  static const approved = LinkStatusResponseStatusEnum._(r'approved');

  /// List of all possible values in this [enum][LinkStatusResponseStatusEnum].
  static const values = <LinkStatusResponseStatusEnum>[
    pending,
    approved,
  ];

  static LinkStatusResponseStatusEnum? fromJson(dynamic value) => LinkStatusResponseStatusEnumTypeTransformer().decode(value);

  static List<LinkStatusResponseStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LinkStatusResponseStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LinkStatusResponseStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [LinkStatusResponseStatusEnum] to String,
/// and [decode] dynamic data back to [LinkStatusResponseStatusEnum].
class LinkStatusResponseStatusEnumTypeTransformer {
  factory LinkStatusResponseStatusEnumTypeTransformer() => _instance ??= const LinkStatusResponseStatusEnumTypeTransformer._();

  const LinkStatusResponseStatusEnumTypeTransformer._();

  String encode(LinkStatusResponseStatusEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a LinkStatusResponseStatusEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  LinkStatusResponseStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'pending': return LinkStatusResponseStatusEnum.pending;
        case r'approved': return LinkStatusResponseStatusEnum.approved;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [LinkStatusResponseStatusEnumTypeTransformer] instance.
  static LinkStatusResponseStatusEnumTypeTransformer? _instance;
}


