import 'dart:io';

import 'package:argosy/features/stow/offline_progress_queue.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what reached the server, and can be told to fail the way an
/// unreachable server does.
class _FakeLibraryApi extends LibraryApi {
  final List<(String, double)> reported = [];
  final List<String> watched = [];

  /// null = succeed; otherwise thrown from every call.
  Object? failure;

  @override
  Future<PlayState?> reportProgress(
    String itemId,
    ProgressUpdate progressUpdate, {
    Future<void>? abortTrigger,
  }) async {
    final f = failure;
    if (f != null) throw f;
    reported.add((itemId, progressUpdate.positionSeconds.toDouble()));
    return null;
  }

  @override
  Future<PlayState?> setWatched(
    String itemId,
    WatchedUpdate watchedUpdate, {
    Future<void>? abortTrigger,
  }) async {
    final f = failure;
    if (f != null) throw f;
    watched.add(itemId);
    return null;
  }
}

void main() {
  late Directory dir;
  late OfflineProgressQueue queue;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('argosy-queue-test');
    queue = OfflineProgressQueue(file: File('${dir.path}/queue.json'));
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('holds a position and delivers it once the server is back', () async {
    await queue.enqueue(
      itemId: 'a',
      positionSeconds: 120,
      durationSeconds: 2400,
    );
    expect(await queue.pendingCount(), 1);

    final api = _FakeLibraryApi();
    expect(await queue.flush(api), 1);
    expect(api.reported, [('a', 120.0)]);
    expect(await queue.pendingCount(), 0);
  });

  test('keeps only the furthest position for an item', () async {
    await queue.enqueue(itemId: 'a', positionSeconds: 100);
    await queue.enqueue(itemId: 'a', positionSeconds: 900);
    // A stale report from a restarted player must not rewind the resume point.
    await queue.enqueue(itemId: 'a', positionSeconds: 30);

    expect(await queue.pendingCount(), 1);
    final api = _FakeLibraryApi();
    await queue.flush(api);
    expect(api.reported, [('a', 900.0)]);
  });

  test('an offline finish still marks watched on reconnect', () async {
    await queue.enqueue(
      itemId: 'a',
      positionSeconds: 2390,
      durationSeconds: 2400,
      watched: true,
    );
    final api = _FakeLibraryApi();
    await queue.flush(api);
    expect(api.watched, ['a']);
  });

  test('a watched flag survives a later position-only report', () async {
    await queue.enqueue(itemId: 'a', positionSeconds: 2390, watched: true);
    await queue.enqueue(itemId: 'a', positionSeconds: 2395);
    final api = _FakeLibraryApi();
    await queue.flush(api);
    expect(
      api.watched,
      ['a'],
      reason: 'finishing offline must not be undone by the next heartbeat',
    );
  });

  test('survives a restart — the queue is the whole point', () async {
    await queue.enqueue(itemId: 'a', positionSeconds: 300);

    final reopened = OfflineProgressQueue(file: File('${dir.path}/queue.json'));
    expect(await reopened.pendingCount(), 1);
    final api = _FakeLibraryApi();
    expect(await reopened.flush(api), 1);
    expect(api.reported, [('a', 300.0)]);
  });

  test('a still-offline flush keeps everything queued', () async {
    await queue.enqueue(itemId: 'a', positionSeconds: 300);
    final api = _FakeLibraryApi()..failure = const SocketException('no route');

    expect(await queue.flush(api), 0);
    expect(await queue.pendingCount(), 1);
  });

  test('drops an entry the server rejects outright', () async {
    await queue.enqueue(itemId: 'gone', positionSeconds: 300);
    // A deleted item 404s forever; retrying it every launch would never work.
    final api = _FakeLibraryApi()..failure = ApiException(404, 'not found');

    await queue.flush(api);
    expect(await queue.pendingCount(), 0);
  });

  group('settled', () {
    test('drops a queued position a live report has overtaken', () async {
      // Watched to 30:00 offline, then the network came back and the heartbeat
      // reported 35:00 directly. Draining the queue blind would write 1800 over
      // 2100 — and if the viewer closes the player right then, no further
      // heartbeat repairs it.
      await queue.enqueue(itemId: 'a', positionSeconds: 1800);
      await queue.settled(itemId: 'a', positionSeconds: 2100);

      expect(await queue.pendingCount(), 0);
      final api = _FakeLibraryApi();
      await queue.flush(api);
      expect(api.reported, isEmpty, reason: 'nothing left to rewind with');
    });

    test('leaves a queued position that is still ahead', () async {
      await queue.enqueue(itemId: 'a', positionSeconds: 2100);
      await queue.settled(itemId: 'a', positionSeconds: 1800);

      expect(await queue.pendingCount(), 1);
      final api = _FakeLibraryApi();
      await queue.flush(api);
      expect(api.reported, [('a', 2100.0)]);
    });

    test('keeps an offline finish but moves it forward', () async {
      await queue.enqueue(itemId: 'a', positionSeconds: 1800, watched: true);
      await queue.settled(itemId: 'a', positionSeconds: 2100);

      final api = _FakeLibraryApi();
      await queue.flush(api);
      expect(api.watched, [
        'a',
      ], reason: 'finishing offline must still be reported');
      expect(api.reported, [
        ('a', 2100.0),
      ], reason: 'and must not rewind the position while doing it');
    });

    test('is a no-op for an item that was never queued', () async {
      await queue.settled(itemId: 'never', positionSeconds: 100);
      expect(await queue.pendingCount(), 0);
    });
  });

  test('keeps an entry a 5xx failed, since that may recover', () async {
    await queue.enqueue(itemId: 'a', positionSeconds: 300);
    final api = _FakeLibraryApi()..failure = ApiException(503, 'unavailable');

    await queue.flush(api);
    expect(await queue.pendingCount(), 1);
  });
}
