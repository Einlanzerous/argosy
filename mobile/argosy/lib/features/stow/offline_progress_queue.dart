import 'dart:convert';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:path_provider/path_provider.dart';

/// One resume position recorded while the server was out of reach.
class _PendingProgress {
  _PendingProgress({
    required this.itemId,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.at,
    required this.watched,
  });

  final String itemId;
  final double positionSeconds;
  final double? durationSeconds;
  final DateTime at;

  /// Set when the item was finished offline, so it leaves Continue Watching on
  /// reconnect the same way an online finish does.
  final bool watched;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'at': at.toIso8601String(),
    'watched': watched,
  };

  static _PendingProgress fromJson(Map<String, dynamic> json) =>
      _PendingProgress(
        itemId: json['itemId'] as String,
        positionSeconds: (json['positionSeconds'] as num?)?.toDouble() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        watched: json['watched'] as bool? ?? false,
      );
}

/// Holds resume positions recorded offline until the server can be told
/// (ARGY-49).
///
/// Watching a stowed episode on a plane still moves your place in it. Without
/// this, the position is reported into a dead socket, swallowed by the
/// fire-and-forget catch in the playback heartbeat, and the episode you finished
/// is still sitting at 0% when you land — with Continue Watching and On-Deck
/// both wrong about where you are.
///
/// One entry per item, holding the furthest point reached: intermediate
/// positions from a single sitting are not interesting, only where you stopped.
class OfflineProgressQueue {
  OfflineProgressQueue({File? file}) : _fileOverride = file;

  final File? _fileOverride;
  File? _file;
  Map<String, _PendingProgress>? _pending;

  Future<File> _ensureFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final f =
        _fileOverride ??
        File(
          '${(await getApplicationSupportDirectory()).path}/stow/progress_queue.json',
        );
    await f.parent.create(recursive: true);
    _file = f;
    return f;
  }

  Future<void> _load() async {
    if (_pending != null) return;
    final file = await _ensureFile();
    if (!await file.exists()) {
      _pending = {};
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
      final entries = decoded
          .map((e) => _PendingProgress.fromJson(e as Map<String, dynamic>))
          .toList();
      _pending = {for (final e in entries) e.itemId: e};
    } catch (_) {
      _pending = {};
    }
  }

  /// Number of positions waiting to be sent.
  Future<int> pendingCount() async {
    await _load();
    return _pending!.length;
  }

  /// Records a position to send later. A later position for the same item
  /// replaces an earlier one; an earlier one is ignored, so a stray report from
  /// a restarted player can't rewind a resume point that was already further on.
  Future<void> enqueue({
    required String itemId,
    required double positionSeconds,
    double? durationSeconds,
    bool watched = false,
  }) async {
    await _load();
    final existing = _pending![itemId];
    if (existing != null &&
        existing.positionSeconds > positionSeconds &&
        !watched) {
      return;
    }
    _pending![itemId] = _PendingProgress(
      itemId: itemId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      at: DateTime.now(),
      watched: watched || (existing?.watched ?? false),
    );
    await _persist();
  }

  /// Records that a position reached the server directly, so a queued entry for
  /// the same item can't later overwrite it with an older one.
  ///
  /// The server's progress write is last-wins with no monotonic guard, so
  /// draining the queue right after a successful live report would send a stale
  /// position over a fresher one. That is not self-correcting at the end of a
  /// session: the final report on dispose triggers the same drain, and no
  /// heartbeat follows to repair it — the resume point stays behind for good.
  ///
  /// A `watched` entry is kept rather than dropped (finishing offline still has
  /// to be reported) but is moved forward, so it can't rewind either.
  Future<void> settled({
    required String itemId,
    required double positionSeconds,
  }) async {
    await _load();
    final existing = _pending![itemId];
    if (existing == null || existing.positionSeconds > positionSeconds) return;

    if (!existing.watched) {
      _pending!.remove(itemId);
    } else {
      _pending![itemId] = _PendingProgress(
        itemId: itemId,
        positionSeconds: positionSeconds,
        durationSeconds: existing.durationSeconds,
        at: existing.at,
        watched: true,
      );
    }
    await _persist();
  }

  /// Sends everything queued. Entries that fail stay queued for the next
  /// attempt; entries the server rejects outright (a deleted item, a 4xx) are
  /// dropped, since retrying them forever would never succeed.
  ///
  /// Returns how many were delivered.
  Future<int> flush(LibraryApi api) async {
    await _load();
    if (_pending!.isEmpty) return 0;

    var sent = 0;
    final delivered = <String>[];
    for (final entry in _pending!.values.toList()) {
      try {
        await api.reportProgress(
          entry.itemId,
          ProgressUpdate(
            positionSeconds: entry.positionSeconds,
            durationSeconds: entry.durationSeconds,
          ),
        );
        if (entry.watched) {
          await api.setWatched(entry.itemId, WatchedUpdate(watched: true));
        }
        delivered.add(entry.itemId);
        sent++;
      } on ApiException catch (e) {
        // 5xx and transport failures are worth retrying; a 4xx never will be.
        if (e.code >= 400 && e.code < 500) {
          delivered.add(entry.itemId);
        } else {
          break; // The server is unwell; stop hammering it this round.
        }
      } catch (_) {
        break; // Still offline.
      }
    }
    if (delivered.isNotEmpty) {
      for (final id in delivered) {
        _pending!.remove(id);
      }
      await _persist();
    }
    return sent;
  }

  Future<void> _persist() async {
    final file = await _ensureFile();
    final snapshot = _pending!.values.map((e) => e.toJson()).toList();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot), flush: true);
    await tmp.rename(file.path);
  }
}
