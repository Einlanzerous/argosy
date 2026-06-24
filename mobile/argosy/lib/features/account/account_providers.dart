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
