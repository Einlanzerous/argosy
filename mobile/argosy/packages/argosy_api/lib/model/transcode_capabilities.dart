//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TranscodeCapabilities {
  /// Returns a new [TranscodeCapabilities] instance.
  TranscodeCapabilities({
    this.available = const [],
    required this.selected,
  });

  /// Encoder backends usable on this host (always includes \"software\").
  List<String> available;

  /// The encoder chosen by the configured preference order.
  String selected;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TranscodeCapabilities &&
    _deepEquality.equals(other.available, available) &&
    other.selected == selected;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (available.hashCode) +
    (selected.hashCode);

  @override
  String toString() => 'TranscodeCapabilities[available=$available, selected=$selected]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'available'] = this.available;
      json[r'selected'] = this.selected;
    return json;
  }

  /// Returns a new [TranscodeCapabilities] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TranscodeCapabilities? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'available'), 'Required key "TranscodeCapabilities[available]" is missing from JSON.');
        assert(json[r'available'] != null, 'Required key "TranscodeCapabilities[available]" has a null value in JSON.');
        assert(json.containsKey(r'selected'), 'Required key "TranscodeCapabilities[selected]" is missing from JSON.');
        assert(json[r'selected'] != null, 'Required key "TranscodeCapabilities[selected]" has a null value in JSON.');
        return true;
      }());

      return TranscodeCapabilities(
        available: json[r'available'] is Iterable
            ? (json[r'available'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        selected: mapValueOfType<String>(json, r'selected')!,
      );
    }
    return null;
  }

  static List<TranscodeCapabilities> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TranscodeCapabilities>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TranscodeCapabilities.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TranscodeCapabilities> mapFromJson(dynamic json) {
    final map = <String, TranscodeCapabilities>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TranscodeCapabilities.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TranscodeCapabilities-objects as value to a dart map
  static Map<String, List<TranscodeCapabilities>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TranscodeCapabilities>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TranscodeCapabilities.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'available',
    'selected',
  };
}

