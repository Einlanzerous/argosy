import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';

/// The account's Fleet — every paired, non-revoked device, freshest first. Used
/// by the account sheet to show the shared playhead across screens. autoDispose
/// so it re-fetches each time the sheet opens.
final fleetDevicesProvider = FutureProvider.autoDispose<List<Device>>((
  ref,
) async {
  final devices = await ref.watch(authApiProvider).listDevices() ?? const [];
  final live = devices.where((d) => !d.revoked).toList()
    ..sort((a, b) {
      final at = a.lastSeenAt ?? a.createdAt;
      final bt = b.lastSeenAt ?? b.createdAt;
      return bt.compareTo(at);
    });
  return live;
});

/// This device's current session (account, profile, device, role). autoDispose so
/// it re-fetches after an in-place profile switch invalidates it (ARGY-85).
final currentSessionProvider = FutureProvider.autoDispose<Session?>(
  (ref) => ref.watch(authApiProvider).getCurrentSession(),
);

/// The account's profiles, for the in-place profile switcher (ARGY-85).
/// autoDispose so the picker re-fetches each time it opens.
final accountProfilesProvider =
    FutureProvider.autoDispose<List<ProfileSummary>>(
  (ref) async => await ref.watch(authApiProvider).listProfiles() ?? const [],
);
