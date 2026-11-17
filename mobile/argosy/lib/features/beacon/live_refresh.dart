import 'dart:async';

/// Keeps already-open screens honest about progress made on ANOTHER device
/// (ARGY-291, the mobile and TV counterpart of web's ARGY-290
/// `web/src/lib/liveProgress.ts`). It decides *when* to refetch; [refresh]
/// decides *what* (see `beaconSyncProvider`).
///
/// Three triggers:
/// * a foreign Beacon `position` event, on a trailing [debounce] so a burst of
///   heartbeats from a playing device collapses to one refetch;
/// * the app returning to the foreground, the mobile counterpart of a tab
///   regaining focus; and
/// * the Beacon stream reconnecting.
///
/// The last two are throttled to one per [throttle]. They exist because Beacon
/// has no replay: whatever was published while the app was backgrounded, or
/// while the stream was down, is gone, and only a refetch recovers it. That is
/// the "watched two episodes elsewhere, opened the app, nothing is marked"
/// report this was filed for.
class LiveRefresh {
  LiveRefresh({
    required this.refresh,
    this.debounce = const Duration(milliseconds: 1500),
    this.throttle = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Invalidates whatever shows progress. Must be cheap and synchronous; the
  /// screens render with stale-while-revalidate, so it never flashes a spinner.
  final void Function() refresh;
  final Duration debounce;
  final Duration throttle;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _last;
  int _opens = 0;
  bool _disposed = false;

  void _run() {
    if (_disposed) return;
    _last = _now();
    refresh();
  }

  /// A position event from another device. Echo suppression is the caller's.
  void onForeignEvent() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      _run();
    });
  }

  /// The app came back to the foreground.
  void onResumed() => _throttled();

  /// The Beacon stream opened. The first open is the initial connect, made as
  /// the app starts and its screens do their own first load, so refetching
  /// then would be a duplicate. Every later open is a reconnect, and a
  /// reconnect is exactly when events were missed.
  void onStreamOpened() {
    if (_opens++ == 0) return;
    _throttled();
  }

  void _throttled() {
    if (_disposed) return;
    final last = _last;
    if (last != null && _now().difference(last) < throttle) return;
    // A pending debounced refetch would only repeat this one.
    _timer?.cancel();
    _timer = null;
    _run();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
