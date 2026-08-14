import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'stowed_item.dart';

/// The on-device record of what has been packed away (ARGY-49).
///
/// Layout under the application support directory:
///
///     stow/
///       index.json          <- every finished stow
///       <itemId>/
///         video.mp4         <- or the source's own extension for a passthrough
///         sub-<trackId>.vtt
///
/// A JSON index rather than a database: the whole point of the record is a list
/// of a few dozen rows read once per screen, and a file the app can rewrite
/// atomically is easier to reason about than a schema that would need its own
/// migrations alongside the server's.
///
/// Paths are stored relative to the stow root and resolved at read time, because
/// iOS moves the application container between launches — an absolute path
/// recorded today is wrong after the next app update.
class StowStore {
  StowStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;

  Directory? _root;
  Map<String, StowedItem>? _index;

  /// Serializes index writes so two downloads finishing together can't
  /// interleave read-modify-write and lose one of the entries.
  Future<void> _writeLock = Future.value();

  static const _indexFile = 'index.json';

  Future<Directory> _ensureRoot() async {
    final cached = _root;
    if (cached != null) return cached;
    final base =
        _rootOverride ??
        Directory('${(await getApplicationSupportDirectory()).path}/stow');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    _root = base;
    return base;
  }

  /// Loads the index from disk. Safe to call repeatedly; only the first call
  /// touches the filesystem.
  Future<void> load() async {
    if (_index != null) return;
    final root = await _ensureRoot();
    final file = File('${root.path}/$_indexFile');
    if (!await file.exists()) {
      _index = {};
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final entries = (decoded as List<dynamic>)
          .map((e) => StowedItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _index = {for (final e in entries) e.itemId: e};
    } catch (_) {
      // A truncated or hand-edited index must not brick the feature. The files
      // on disk are still there; reconcile() below re-finds anything playable.
      _index = {};
    }
    await _reconcile();
  }

  /// Drops index entries whose video file has gone (an OS cleanup, a manual
  /// delete, a restore onto a new device). Without this the Stowed screen offers
  /// rows that fail the moment they are tapped.
  Future<void> _reconcile() async {
    final index = _index;
    if (index == null || index.isEmpty) return;
    final missing = <String>[];
    for (final entry in index.values) {
      if (!await File(await videoPath(entry)).exists()) {
        missing.add(entry.itemId);
      }
    }
    if (missing.isEmpty) return;
    for (final id in missing) {
      index.remove(id);
    }
    await _persist();
  }

  /// Every stowed item, most recently stowed first.
  List<StowedItem> list() {
    final index = _index;
    if (index == null) return const [];
    final out = index.values.toList()
      ..sort((a, b) => b.stowedAt.compareTo(a.stowedAt));
    return out;
  }

  StowedItem? get(String itemId) => _index?[itemId];

  bool has(String itemId) => _index?.containsKey(itemId) ?? false;

  /// Total bytes held by stowed items, for the storage line on the Stowed
  /// screen.
  int totalBytes() =>
      _index?.values.fold<int>(0, (sum, e) => sum + e.bytes) ?? 0;

  /// The directory an item's files live in (created on demand).
  Future<Directory> itemDir(String itemId) async {
    final root = await _ensureRoot();
    final dir = Directory('${root.path}/$itemId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Absolute path to a stowed item's video file.
  Future<String> videoPath(StowedItem item) async {
    final root = await _ensureRoot();
    return '${root.path}/${item.itemId}/${item.fileName}';
  }

  /// Absolute path to one of a stowed item's sidecar subtitle files.
  Future<String> subtitlePath(StowedItem item, StowedSubtitle track) async {
    final root = await _ensureRoot();
    return '${root.path}/${item.itemId}/${track.fileName}';
  }

  /// Records a finished stow.
  Future<void> put(StowedItem item) async {
    await load();
    _index![item.itemId] = item;
    await _persist();
  }

  /// Removes an item: its index entry and every file it brought with it.
  Future<void> remove(String itemId) async {
    await load();
    _index!.remove(itemId);
    await _persist();
    final root = await _ensureRoot();
    final dir = Directory('${root.path}/$itemId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Clears a half-finished download's directory without touching the index —
  /// used when a stow is cancelled or fails partway.
  Future<void> discardPartial(String itemId) async {
    if (has(itemId)) return; // A finished stow; leave it alone.
    final root = await _ensureRoot();
    final dir = Directory('${root.path}/$itemId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _persist() {
    final snapshot = list().map((e) => e.toJson()).toList();
    // Chain onto the previous write rather than racing it.
    _writeLock = _writeLock.then((_) async {
      final root = await _ensureRoot();
      final target = File('${root.path}/$_indexFile');
      // Write-then-rename: a crash mid-write leaves the previous index intact
      // instead of a half-written file that reads as "nothing is stowed".
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(jsonEncode(snapshot), flush: true);
      await tmp.rename(target.path);
    });
    return _writeLock;
  }
}
