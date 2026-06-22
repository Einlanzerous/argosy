import 'dart:convert';

/// A live play-state change broadcast by the server's Beacon hub, mirroring the
/// Go `beacon.Event` (`internal/beacon/beacon.go`) and the web client's
/// `BeaconEvent` (`web/src/lib/beacon.ts`). Delivered as the `data` payload of
/// an `event: position` SSE frame on `GET /api/v1/beacon?token=`.
///
/// There is no generated model for this — the catalog's [PlayState] lacks the
/// `userId`/`itemId`/`originDeviceId` fields that make cross-device routing and
/// echo-suppression possible — so it is parsed by hand here.
class BeaconEvent {
  const BeaconEvent({
    required this.userId,
    required this.itemId,
    required this.positionSeconds,
    this.durationSeconds,
    required this.watched,
    this.originDeviceId,
    this.updatedAt,
  });

  final String userId;
  final String itemId;
  final double positionSeconds;
  final double? durationSeconds;
  final bool watched;

  /// The device that produced this update. Used to drop echoes of our own
  /// progress reports (we already reflect those locally).
  final String? originDeviceId;
  final DateTime? updatedAt;

  /// Parses one `data:` payload. Returns null for malformed frames or any
  /// payload missing the load-bearing `itemId`, so callers can skip it.
  static BeaconEvent? tryParse(String data) {
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final itemId = decoded['itemId'];
    if (itemId is! String || itemId.isEmpty) return null;
    return BeaconEvent(
      userId: decoded['userId'] as String? ?? '',
      itemId: itemId,
      positionSeconds: (decoded['positionSeconds'] as num?)?.toDouble() ?? 0,
      durationSeconds: (decoded['durationSeconds'] as num?)?.toDouble(),
      watched: decoded['watched'] as bool? ?? false,
      originDeviceId: decoded['originDeviceId'] as String?,
      updatedAt: DateTime.tryParse(decoded['updatedAt'] as String? ?? ''),
    );
  }
}
