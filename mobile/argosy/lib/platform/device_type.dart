import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is running on a TV / leanback device (Android TV, Google TV).
///
/// Detection is async (a platform-channel call), so we resolve it once in
/// `main()` before `runApp` and inject the result by overriding this provider in
/// the root [ProviderScope]. Reading it is therefore synchronous everywhere —
/// `app.dart` uses it to pick the TV shell vs. the touch shell (ARGY-51).
///
/// The default throws so a missing override is a loud bug, not a silent "phone".
final isTelevisionProvider = Provider<bool>(
  (ref) => throw StateError('isTelevisionProvider must be overridden in main()'),
);
