import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'beacon_event.dart';

/// An EventSource-style consumer of the Beacon SSE stream
/// (`GET /api/v1/beacon?token=`). Dart has no built-in `EventSource`, so this
/// holds a streamed HTTP request open, parses `text/event-stream` frames by
/// hand, and reconnects with exponential backoff — mirroring the auto-reconnect
/// the browser's EventSource gives the web client for free.
///
/// It only surfaces `position` events (the one frame the Beacon hub emits;
/// `: ping` comment lines keep the connection warm and are ignored). Echo
/// suppression — dropping our own device's updates — is the caller's job, since
/// only the caller knows this device's id.
class BeaconClient {
  BeaconClient({
    required this.resolveUrl,
    http.Client? httpClient,
    this.baseBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Resolved per connect so a token/base-URL change (re-pair, server switch)
  /// is picked up on the next reconnect without rebuilding the client.
  final Uri Function() resolveUrl;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final http.Client _http;
  final bool _ownsHttp;

  final _controller = StreamController<BeaconEvent>.broadcast();

  bool _started = false;
  bool _closed = false;
  int _attempt = 0;
  Timer? _retry;
  StreamSubscription<String>? _lines;

  /// Broadcast stream of position events. Listen before [start] to catch the
  /// first ones.
  Stream<BeaconEvent> get events => _controller.stream;

  /// Opens the stream and keeps it open across reconnects. Idempotent.
  void start() {
    if (_started || _closed) return;
    _started = true;
    _connect();
  }

  Future<void> _connect() async {
    if (_closed) return;
    final url = resolveUrl();
    // No token yet (signed out / mid-bootstrap) — there's nothing to stream;
    // back off and check again rather than firing a doomed request.
    if ((url.queryParameters['token'] ?? '').isEmpty) {
      _scheduleReconnect();
      return;
    }

    http.StreamedResponse resp;
    try {
      final req = http.Request('GET', url)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      resp = await _http.send(req);
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    if (_closed) return;
    if (resp.statusCode != 200) {
      // 401 (token expired), 503 (starting), etc. — drain and retry.
      _scheduleReconnect();
      return;
    }

    var event = 'message';
    final data = StringBuffer();
    _lines = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        // Any byte off the wire proves the connection is healthy, so reset the
        // backoff — a long-lived stream shouldn't accrue penalty over hours.
        _attempt = 0;
        if (line.isEmpty) {
          // Blank line terminates a frame: dispatch what we accumulated.
          if (data.isNotEmpty && event == 'position') {
            final ev = BeaconEvent.tryParse(data.toString());
            if (ev != null && !_controller.isClosed) _controller.add(ev);
          }
          event = 'message';
          data.clear();
          return;
        }
        if (line.startsWith(':')) return; // comment / keep-alive ping
        final colon = line.indexOf(':');
        final field = colon == -1 ? line : line.substring(0, colon);
        var value = colon == -1 ? '' : line.substring(colon + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        switch (field) {
          case 'event':
            event = value;
          case 'data':
            if (data.isNotEmpty) data.write('\n');
            data.write(value);
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    _lines?.cancel();
    _lines = null;
    if (_closed) return;
    _retry?.cancel();
    final delay = _backoffFor(_attempt);
    _attempt++;
    _retry = Timer(delay, _connect);
  }

  /// Exponential backoff capped at [maxBackoff]: base, 2×, 4×, … The shift is
  /// clamped so it can't overflow at high attempt counts.
  Duration _backoffFor(int attempt) {
    final factor = attempt >= 16 ? (1 << 16) : (1 << attempt);
    final ms = baseBackoff.inMilliseconds * factor;
    return ms >= maxBackoff.inMilliseconds ? maxBackoff : Duration(milliseconds: ms);
  }

  /// Closes the stream and stops reconnecting. The client is single-use after.
  void dispose() {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    _lines?.cancel();
    _lines = null;
    if (!_controller.isClosed) _controller.close();
    if (_ownsHttp) _http.close();
  }
}
