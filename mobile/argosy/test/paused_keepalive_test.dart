import 'dart:io';

import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy/features/stow/offline_progress_queue.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A paused player's position is whatever it was when it paused, and another
/// device may have saved a newer one since. The paused heartbeat exists only to
/// keep the transcode session alive (ARGY-239), so it must say so (ARGY-289):
/// a plain position write from it — or its offline replay later — put the older
/// position over the newer one.
class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  final reports = <ProgressUpdate>[];

  /// null = succeed; otherwise thrown from every call, as an unreachable
  /// server does.
  Object? failure;

  @override
  Future<PlayState?> reportProgress(
    String itemId,
    ProgressUpdate progressUpdate, {
    Future<void>? abortTrigger,
  }) async {
    reports.add(progressUpdate);
    final f = failure;
    if (f != null) throw f;
    return null;
  }
}

/// Lets the fire-and-forget report, its failure handler and the queue's file
/// write finish.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late OfflineProgressQueue queue;
  late _Library library;
  late PlaybackController c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('argosy-keepalive-test');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    queue = OfflineProgressQueue(file: File('${dir.path}/queue.json'));
    library = _Library();
    c = PlaybackController(
      libraryApi: library,
      transcodeApi: TranscodeApi(ApiClient()),
      authApi: AuthApi(ApiClient()),
      baseUrl: 'http://localhost',
      token: null,
      itemId: 'item-1',
      title: 'Futurama s03e05',
      catalogDuration: 1355.872,
      isTranscode: true,
      hevc: true,
      hevcHardware: true,
      subtitles: const [],
      preferredLanguages: const [],
      prefs: null,
      offlineQueue: queue,
    );
    // Paused (VideoPlayerValue.isPlaying defaults to false) 100s into a session
    // that started at 500s, with a live session to keep.
    c.baseOffset = 500;
    c.debugVideoValue = VideoPlayerValue(
      duration: const Duration(seconds: 309),
      position: const Duration(seconds: 100),
    );
    c.debugSessionId = 's500';
    addTearDown(() async {
      // Succeed, so dispose's own final flush queues nothing into a directory
      // that is about to go.
      library.failure = null;
      c.debugSessionId = null; // no stopTranscode to a server that isn't there
      c.dispose();
      await settle();
    });
  });

  test('the paused heartbeat sends keepalive: true', () async {
    c.debugHeartbeatTick(DateTime.now());
    await settle();

    expect(library.reports, hasLength(1));
    expect(library.reports.single.keepalive, isTrue);
    expect(library.reports.single.positionSeconds, closeTo(600, 0.001));
  });

  test('a failed paused heartbeat is not queued for replay', () async {
    library.failure = const SocketException('Network is unreachable');

    c.debugHeartbeatTick(DateTime.now());
    await settle();

    expect(library.reports, hasLength(1));
    expect(library.reports.single.keepalive, isTrue);
    expect(await queue.pendingCount(), 0);
  });

  test('an ordinary flush is a plain write and still queues on failure',
      () async {
    library.failure = const SocketException('Network is unreachable');

    c.debugFlush();
    await settle();

    expect(library.reports, hasLength(1));
    expect(library.reports.single.keepalive, isNull);
    expect(library.reports.single.positionSeconds, closeTo(600, 0.001));
    expect(await queue.pendingCount(), 1);
  });
}
