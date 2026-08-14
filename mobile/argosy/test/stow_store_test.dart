import 'dart:io';

import 'package:argosy/features/browse/media_card.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/features/stow/stowed_item.dart';
import 'package:flutter_test/flutter_test.dart';

StowedItem _item(String id, {int bytes = 100, String file = 'video.mp4'}) =>
    StowedItem(
      itemId: id,
      title: 'Title $id',
      fileName: file,
      bytes: bytes,
      stowedAt: DateTime(2026, 8, 14),
    );

/// Creates the video file a store entry claims to have, so reconcile() keeps it.
Future<void> _writeVideo(StowStore store, StowedItem item) async {
  final dir = await store.itemDir(item.itemId);
  await File('${dir.path}/${item.fileName}').writeAsString('x' * item.bytes);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-stow-test');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  StowStore newStore() => StowStore(root: root);

  test('records a stow and reports it back', () async {
    final store = newStore();
    await store.load();

    final item = _item('a');
    await _writeVideo(store, item);
    await store.put(item);

    expect(store.has('a'), isTrue);
    expect(store.get('a')?.title, 'Title a');
    expect(store.totalBytes(), 100);
    expect(await store.videoPath(item), endsWith('/a/video.mp4'));
  });

  test('survives a reload — the index is what makes a stow durable', () async {
    final first = newStore();
    await first.load();
    final item = _item('a');
    await _writeVideo(first, item);
    await first.put(item);

    final second = newStore();
    await second.load();
    expect(second.has('a'), isTrue);
    expect(second.get('a')?.bytes, 100);
  });

  test('lists newest first', () async {
    final store = newStore();
    await store.load();
    for (final (id, day) in [('old', 1), ('new', 20), ('mid', 10)]) {
      final item = StowedItem(
        itemId: id,
        title: id,
        fileName: 'video.mp4',
        bytes: 10,
        stowedAt: DateTime(2026, 8, day),
      );
      await _writeVideo(store, item);
      await store.put(item);
    }
    expect(store.list().map((e) => e.itemId), ['new', 'mid', 'old']);
  });

  test('remove deletes the files, not just the row', () async {
    final store = newStore();
    await store.load();
    final item = _item('a');
    await _writeVideo(store, item);
    await store.put(item);
    final dir = Directory('${root.path}/a');
    expect(await dir.exists(), isTrue);

    await store.remove('a');

    expect(store.has('a'), isFalse);
    expect(store.totalBytes(), 0);
    expect(await dir.exists(), isFalse, reason: 'the bytes must be reclaimed');
  });

  test('drops entries whose file has vanished', () async {
    final first = newStore();
    await first.load();
    final item = _item('a');
    await _writeVideo(first, item);
    await first.put(item);

    // Simulate an OS cleanup / restore onto a new device.
    await Directory('${root.path}/a').delete(recursive: true);

    final second = newStore();
    await second.load();
    expect(
      second.has('a'),
      isFalse,
      reason: 'a row with no file would offer a download that fails when tapped',
    );
  });

  test('a corrupt index degrades to empty instead of throwing', () async {
    await File('${root.path}/index.json').writeAsString('{not json');
    final store = newStore();
    await store.load();
    expect(store.list(), isEmpty);
  });

  test('discardPartial clears a cancelled download but spares a finished one',
      () async {
    final store = newStore();
    await store.load();

    // A download that never finished: no index entry, but bytes on disk.
    final dir = await store.itemDir('partial');
    await File('${dir.path}/video.mp4.part').writeAsString('half');
    await store.discardPartial('partial');
    expect(await Directory('${root.path}/partial').exists(), isFalse);

    // A finished stow must be untouchable by the same call.
    final done = _item('done');
    await _writeVideo(store, done);
    await store.put(done);
    await store.discardPartial('done');
    expect(store.has('done'), isTrue);
    expect(await File(await store.videoPath(done)).exists(), isTrue);
  });

  test('round-trips episode fields and subtitle sidecars', () async {
    final first = newStore();
    await first.load();
    final item = StowedItem(
      itemId: 'ep',
      title: 'The Show',
      subtitleLine: 'S2 · E4 · Some Episode',
      fileName: 'video.mp4',
      bytes: 42,
      durationSeconds: 2700,
      stowedAt: DateTime(2026, 8, 14),
      kind: MediaKind.series,
      seasonNumber: 2,
      episodeNumber: 4,
      subtitles: const [
        StowedSubtitle(
          id: 'track-1',
          label: 'English',
          language: 'en',
          fileName: 'sub-track-1.vtt',
        ),
      ],
    );
    await _writeVideo(first, item);
    await first.put(item);

    final second = newStore();
    await second.load();
    final got = second.get('ep')!;
    expect(got.kind, MediaKind.series);
    expect(got.seasonNumber, 2);
    expect(got.episodeNumber, 4);
    expect(got.subtitleLine, 'S2 · E4 · Some Episode');
    expect(got.durationSeconds, 2700);
    expect(got.subtitles.single.language, 'en');
    expect(
      await second.subtitlePath(got, got.subtitles.single),
      endsWith('/ep/sub-track-1.vtt'),
    );
  });
}
