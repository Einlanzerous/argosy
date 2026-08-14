import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../api/api_providers.dart';
import '../../api/token_store.dart';
import 'stow_runner.dart';
import 'stow_store.dart';
import 'stowed_item.dart';

/// Runs stows somewhere the app isn't (ARGY-201).
///
/// A stow used to advance only while the app was in the foreground: the
/// transfer was a plain HTTP stream on the UI isolate, so backgrounding the
/// phone stopped it and swiping the app away killed the engine that owned it.
/// Nothing was lost — bytes stay in a `.part` and a return to the app resumed
/// them — but it meant watching a progress bar for the length of a 2 GB
/// download, which is not how anyone puts a film on a phone before a flight.
///
/// So the transfer moves into a foreground service's own isolate. That isolate
/// has no widget tree and outlives the activity, which is exactly the point:
/// Android keeps the process alive for a foreground service, and restarts the
/// service if it ever does reclaim it. [StowRunner] is deliberately
/// Flutter-free so the same code runs here and, on iOS or under test, straight
/// in the app.
///
/// The notification is not decoration: an ongoing foreground service must show
/// one, and it is the only surface a user has for a transfer while the app is
/// closed — hence the progress text and the Cancel action.

/// Notification channel + service identity.
const _channelId = 'dev.dodson.argosy.stow';
const _serviceId = 4901;

/// Manifest meta-data naming the monochrome status-bar drawable. The default is
/// the launcher icon, which Android masks to its alpha channel and renders as a
/// white blob.
const _iconMetaData = 'dev.dodson.argosy.STOW_NOTIFICATION_ICON';

/// The Cancel action on the notification.
const _cancelButtonId = 'stow_cancel';

/// Where the service keeps the jobs it still owes.
const _queueKey = 'stow.queue';

/// Message tags. The two isolates exchange JSON strings rather than live
/// objects; anything crossing has to survive `jsonEncode`.
const _msgReady = 'ready';
const _msgEvent = 'event';
const _msgSync = 'sync';
const _msgEnqueue = 'enqueue';
const _msgCancel = 'cancel';
const _msgRemove = 'remove';

String _encode(String type, [Map<String, dynamic> body = const {}]) =>
    jsonEncode({'t': type, ...body});

/// Whatever drives stows for this platform: the foreground service on Android,
/// the app itself everywhere else.
abstract class StowEngine {
  /// Progress, completion and index changes, wherever they happened.
  Stream<StowEvent> get events;

  Future<void> enqueue(StowJobRequest job);

  Future<void> cancel(String itemId);

  Future<void> remove(String itemId);

  /// Asks for the state of anything already running, replayed through
  /// [events]. Called when the UI attaches to a transfer it did not start —
  /// after a relaunch, with the service still going.
  Future<void> sync();

  void dispose();
}

/// Runs stows in the app's own isolate.
///
/// Used on iOS, where background execution is a different mechanism entirely
/// (`URLSession` background transfers) and Stow is Android-first, and in tests,
/// where there is no platform to host a service.
class LocalStowEngine implements StowEngine {
  LocalStowEngine({
    required StowStore store,
    required Future<StowSession> Function() connect,
  }) {
    _runner = StowRunner(store: store, connect: connect, onEvent: _events.add);
  }

  final _events = StreamController<StowEvent>.broadcast();
  late final StowRunner _runner;

  @override
  Stream<StowEvent> get events => _events.stream;

  @override
  Future<void> enqueue(StowJobRequest job) => _runner.enqueue(job);

  @override
  Future<void> cancel(String itemId) => _runner.cancel(itemId);

  @override
  Future<void> remove(String itemId) => _runner.remove(itemId);

  @override
  Future<void> sync() async {
    _runner.statuses.forEach(
      (itemId, status) =>
          _events.add(StowEvent(itemId: itemId, status: status)),
    );
  }

  /// Settles when the queue has drained — the hook tests wait on.
  Future<void> get done => _runner.done;

  @override
  void dispose() => _events.close();
}

/// Runs stows inside an Android foreground service.
class ForegroundStowEngine implements StowEngine {
  ForegroundStowEngine({required this.store}) {
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  /// Only touched when there is no service running — see [_forward].
  final StowStore store;
  final _events = StreamController<StowEvent>.broadcast();
  Completer<void>? _ready;

  @override
  Stream<StowEvent> get events => _events.stream;

  @override
  Future<void> enqueue(StowJobRequest job) async {
    if (await _offer(job)) return;
    // The message went nowhere. The likeliest reason is that the service was
    // already shutting down when it was sent — it stops itself once its queue
    // drains, and "is it running?" can be true right up until it isn't. Nothing
    // else would notice: the job is simply gone, and the button sits on
    // "Preparing…" forever. So try once more against a service we just started.
    if (await _offer(job)) return;
    throw const ApiFailure("The download service didn't pick this up.");
  }

  /// Hands [job] to the service and waits to hear that it landed.
  Future<bool> _offer(StowJobRequest job) async {
    await _ensureRunning();
    final acknowledged = _events.stream
        .firstWhere((e) => e.itemId == job.itemId)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => const StowEvent.idle(),
        )
        .then((e) => !e.isIdle);
    FlutterForegroundTask.sendDataToTask(
      _encode(_msgEnqueue, {'job': job.toJson()}),
    );
    return acknowledged;
  }

  @override
  Future<void> cancel(String itemId) => _forward(_msgCancel, itemId, () async {
    // Nothing is running, so there is no transfer to interrupt — just the bytes
    // an earlier attempt left behind.
    await store.discardPartial(itemId);
  });

  @override
  Future<void> remove(String itemId) => _forward(_msgRemove, itemId, () async {
    await store.remove(itemId);
  });

  @override
  Future<void> sync() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask(_encode(_msgSync));
  }

  /// Sends a command to the service, or does the equivalent here when there is
  /// no service running. Deliberately does *not* start one: cancelling or
  /// deleting is not a reason to raise a foreground service and its
  /// notification.
  Future<void> _forward(
    String type,
    String itemId,
    Future<void> Function() offline,
  ) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(_encode(type, {'itemId': itemId}));
      return;
    }
    await offline();
    _events.add(StowEvent(itemId: itemId, indexChanged: true));
  }

  Future<void> _ensureRunning() async {
    if (await FlutterForegroundTask.isRunningService) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Downloads',
        channelDescription: 'Progress for items being stowed for offline use.',
        // Quiet by design: this is a progress readout, not news. LOW importance
        // and priority are the plugin's defaults and are left as they are;
        // onlyAlertOnce keeps a per-second progress update from re-alerting.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The runner drives itself; there is no periodic work to schedule.
        eventAction: ForegroundTaskEventAction.nothing(),
        // A download is exactly the case for holding the radio awake: the phone
        // is in a pocket with the screen off, which is when a plain transfer
        // stalls. (The CPU wake lock is on by default and wanted here too.)
        allowWifiLock: true,
        // Survive the app being swiped out of Recents. Being restarted after
        // the system reclaims the process is the plugin's default and is what
        // the persisted queue exists for. Not `autoRunOnBoot`: Android 15
        // forbids a BOOT_COMPLETED receiver from launching a dataSync service.
        stopWithTask: false,
      ),
    );

    // Android 13+ won't show the notification without this. The service still
    // runs if it is refused, so a refusal costs visibility, not the download.
    await FlutterForegroundTask.requestNotificationPermission();

    final ready = _ready = Completer<void>();
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Stowing',
      notificationText: 'Preparing…',
      notificationIcon: const NotificationIcon(metaDataName: _iconMetaData),
      notificationButtons: const [
        NotificationButton(id: _cancelButtonId, text: 'Cancel'),
      ],
      callback: stowServiceCallback,
    );
    if (result is ServiceRequestFailure) {
      _ready = null;
      throw ApiFailure("Couldn't start the download service: ${result.error}");
    }
    // The service being up is not the same as its isolate being ready to
    // receive: `startService` returns once Android reports the service running,
    // while the handler's onStart is still on its way. A job sent into that gap
    // is simply dropped, so wait for the handler to announce itself. The
    // timeout is a backstop — losing the announcement should not mean losing
    // the ability to stow.
    await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  void _onData(Object data) {
    if (data is! String) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (message['t']) {
      case _msgReady:
        if (_ready?.isCompleted == false) _ready!.complete();
      case _msgEvent:
        _events.add(
          StowEvent.fromJson(message['event'] as Map<String, dynamic>),
        );
      case _msgSync:
        final statuses = message['statuses'] as Map<String, dynamic>? ?? {};
        statuses.forEach(
          (itemId, status) => _events.add(
            StowEvent(
              itemId: itemId,
              status: StowStatus.fromJson(status as Map<String, dynamic>),
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    _events.close();
  }
}

/// The service isolate's entrypoint. Must stay top-level and annotated: the
/// engine hands it to Android as a callback, and it is looked up by symbol.
@pragma('vm:entry-point')
void stowServiceCallback() {
  FlutterForegroundTask.setTaskHandler(StowTaskHandler());
}

/// The download service, as it runs inside its own isolate.
class StowTaskHandler extends TaskHandler {
  StowRunner? _runner;
  DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _shutdown;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final StowRunner runner;
    try {
      final store = StowStore();
      await store.load();
      runner = _runner = StowRunner(
        store: store,
        connect: _connect,
        onEvent: _onEvent,
        queue: const ForegroundStowQueue(),
      );
    } catch (_) {
      // Without a store there is nothing this service can do, and a service
      // that stays up doing nothing is a notification the user can't dismiss.
      FlutterForegroundTask.sendDataToMain(_encode(_msgReady));
      unawaited(FlutterForegroundTask.stopService());
      return;
    }
    FlutterForegroundTask.sendDataToMain(_encode(_msgReady));
    // Anything the queue still holds was interrupted rather than finished — the
    // system reclaimed the process mid-transfer and has just restarted us. Pick
    // it up without waiting to be asked; the download resumes from its `.part`.
    await runner.restore();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Nothing to save: the queue is persisted as it changes, and a partial
    // download is already on disk with the validator that lets it resume.
    _shutdown?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    final runner = _runner;
    if (runner == null || data is! String) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final itemId = message['itemId'] as String?;
    switch (message['t']) {
      case _msgEnqueue:
        unawaited(
          runner.enqueue(
            StowJobRequest.fromJson(message['job'] as Map<String, dynamic>),
          ),
        );
      case _msgCancel:
        if (itemId != null) unawaited(runner.cancel(itemId));
      case _msgRemove:
        if (itemId != null) unawaited(runner.remove(itemId));
      case _msgSync:
        FlutterForegroundTask.sendDataToMain(
          _encode(_msgSync, {
            'statuses': runner.statuses.map(
              (itemId, status) => MapEntry(itemId, status.toJson()),
            ),
          }),
        );
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _cancelButtonId) return;
    final active = _runner?.activeJob;
    if (active != null) unawaited(_runner!.cancel(active.itemId));
  }

  void _onEvent(StowEvent event) {
    FlutterForegroundTask.sendDataToMain(
      _encode(_msgEvent, {'event': event.toJson()}),
    );
    if (!event.isIdle) {
      _shutdown?.cancel();
      _shutdown = null;
      _updateNotification();
      return;
    }
    // Nothing left to do. A foreground service that outlives its work is a
    // notification the user cannot dismiss, so it stops itself — but not on the
    // instant, because stopping is the one moment a job handed over from the app
    // can fall between the two isolates. Someone stowing a second item right as
    // the first lands is the common case, and this makes it a no-op instead of a
    // restart.
    _shutdown?.cancel();
    _shutdown = Timer(const Duration(seconds: 3), () {
      if (_runner?.isIdle ?? true) {
        unawaited(FlutterForegroundTask.stopService());
      }
    });
  }

  void _updateNotification() {
    final runner = _runner;
    final job = runner?.activeJob;
    if (runner == null || job == null) return;
    // Progress ticks several times a second; each update crosses to the
    // platform and redraws a notification nobody is reading that closely.
    final now = DateTime.now();
    if (now.difference(_lastNotification) < const Duration(seconds: 1)) {
      return;
    }
    _lastNotification = now;

    final status = runner.statuses[job.itemId];
    final queued = runner.pendingCount;
    final text = [
      status?.label ?? 'Preparing…',
      if (queued > 0) '$queued more queued',
    ].join(' · ');
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: job.title,
        notificationText: text,
      ),
    );
  }

  /// Opens a connection using the credentials in secure storage.
  ///
  /// Read here rather than passed in with the job: the token would otherwise
  /// have to be persisted alongside the queue in plain SharedPreferences to
  /// survive a restart, and the whole reason it lives in secure storage is that
  /// it is a bearer credential for the household.
  static Future<StowSession> _connect() async {
    final tokens = TokenStore(const FlutterSecureStorage());
    await tokens.load();
    final baseUrl = tokens.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw const ApiFailure('This device is not paired with a server.');
    }
    return StowSession.connect(baseUrl: baseUrl, token: tokens.token);
  }
}

/// The service's queue, persisted so a restart resumes rather than forgets.
///
/// Deliberately holds job descriptions only — no credentials. See
/// [StowTaskHandler._connect].
class ForegroundStowQueue implements StowQueueStore {
  const ForegroundStowQueue();

  @override
  Future<List<StowJobRequest>> load() async {
    final raw = await FlutterForegroundTask.getData<String>(key: _queueKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => StowJobRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<StowJobRequest> jobs) async {
    await FlutterForegroundTask.saveData(
      key: _queueKey,
      value: jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }
}
