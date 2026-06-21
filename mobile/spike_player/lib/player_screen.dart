import 'dart:async';
import 'dart:convert';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api.dart';

/// The spike's validation surface. Drives the real server through the full
/// playback path and exposes a debug log so each checklist item is observable.
class PlayerScreen extends StatefulWidget {
  final ApiClient api;
  final String itemId;
  final String title;
  const PlayerScreen(
      {super.key, required this.api, required this.itemId, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _pipKey = GlobalKey();
  BetterPlayerController? _controller;
  final List<String> _log = [];
  String? _transcodeSessionId;
  double _startOffset = 0; // movie-time at the player's 0 position (transcode startAt)
  Timer? _heartbeat;
  http.Client? _beaconClient;
  bool _forceTranscode = false;
  bool _ignoreResume = false;

  void _logLine(String s) {
    // ignore: avoid_print
    print('[spike] $s');
    if (mounted) setState(() => _log.insert(0, s));
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final api = widget.api;
      _startOffset = 0;
      final info = await api.playback(widget.itemId);
      _logLine('playback: directPlay=${info['directPlay']} '
          'method=${info['method']} container=${info['container']} '
          'video=${info['videoCodec']} audio=${info['audioCodec']}');

      final ps = await api.progress(widget.itemId);
      final resume =
          _ignoreResume ? 0.0 : ((ps?['positionSeconds'] as num?)?.toDouble() ?? 0);
      final dur = (ps?['durationSeconds'] as num?)?.toDouble();
      if (resume > 0) _logLine('resume from ${resume.toStringAsFixed(0)}s');

      final subs = await api.subtitles(widget.itemId);
      _logLine('subtitle tracks: ${subs.length}');
      final subSources = <BetterPlayerSubtitlesSource>[
        for (final t in subs)
          BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.network,
            name: '${t['label']} (${t['language']})',
            urls: [api.subtitleUrl(widget.itemId, t['id'] as String)],
            selectedByDefault: t['default'] == true,
          ),
      ];

      final direct = info['directPlay'] == true && !_forceTranscode;
      late BetterPlayerDataSource ds;
      if (direct) {
        _logLine('DIRECT PLAY → /stream?token=');
        ds = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          api.streamUrl(widget.itemId),
          subtitles: subSources,
          notificationConfiguration: BetterPlayerNotificationConfiguration(
              showNotification: true, title: widget.title, author: 'Argosy'),
        );
      } else {
        // Advertise HEVC so true-4K HEVC is remuxed at native res, not down-rezzed.
        final t = await api.startTranscode(widget.itemId,
            startAt: resume, hevc: true);
        _startOffset = resume; // HLS timeline is 0-based from startAt
        _transcodeSessionId = t['id'] as String;
        final playlist = api.absolute(t['playlistUrl'] as String);
        _logLine('TRANSCODE method=${t['method']} encoder=${t['encoder']} '
            'state=${t['state']}');
        _logLine('HLS playlist (Bearer header, no ?token=): $playlist');
        ds = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          playlist,
          videoFormat: BetterPlayerVideoFormat.hls,
          // SPIKE FINDING — neither value is correct with the current server:
          //   false → ExoPlayer treats the still-growing transcode playlist as a
          //           finished short VOD, hits a premature end → replay/loop.
          //   true  → plays continuously BUT live = non-seekable: no scrub bar,
          //           no lock-screen transport controls.
          // hls.js (web) tolerates the growing playlist; ExoPlayer does not.
          // Real fix is server-side: emit a seekable manifest with known full
          // duration (VOD) or EXT-X-PLAYLIST-TYPE:EVENT, not an early ENDLIST.
          liveStream: true,
          // THE S1 TEST: does ExoPlayer carry this header to the .m3u8 AND .m4s?
          headers: api.authHeaders,
          subtitles: subSources,
          notificationConfiguration: BetterPlayerNotificationConfiguration(
              showNotification: true, title: widget.title, author: 'Argosy'),
        );
      }

      final controller = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          fit: BoxFit.contain,
          handleLifecycle: false, // keep playing when we enter PiP/background
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            enablePip: true,
            enableSubtitles: true,
            enablePlaybackSpeed: true,
            enableQualities: false,
          ),
        ),
      );
      controller.addEventsListener(_onEvent);
      await controller.setupDataSource(ds);

      // Direct play seeks client-side; transcode already started at the offset.
      if (direct && resume > 0) {
        await controller.seekTo(Duration(seconds: resume.toInt()));
      }

      setState(() => _controller = controller);
      _startHeartbeat(dur);
      _startBeacon();
    } catch (e) {
      _logLine('ERROR: $e');
    }
  }

  void _onEvent(BetterPlayerEvent e) {
    switch (e.betterPlayerEventType) {
      case BetterPlayerEventType.pipStart:
        _logLine('PiP: entered ✅');
        break;
      case BetterPlayerEventType.pipStop:
        _logLine('PiP: exited');
        break;
      case BetterPlayerEventType.exception:
        _logLine('player exception: ${e.parameters}');
        break;
      case BetterPlayerEventType.setupDataSource:
        _logLine('data source ready');
        break;
      default:
        break;
    }
  }

  void _startHeartbeat(double? dur) {
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = _controller?.videoPlayerController?.value.position;
      if (pos == null) return;
      final secs = pos.inMilliseconds / 1000.0 + _startOffset; // → absolute movie-time
      await widget.api.reportProgress(widget.itemId, secs, dur);
      _logLine('heartbeat → ${secs.toStringAsFixed(0)}s (offset ${_startOffset.toStringAsFixed(0)})');
    });
  }

  /// Subscribes to the Beacon SSE stream; surfaces position events that
  /// originate from *another* device for this item (cross-device resume).
  Future<void> _startBeacon() async {
    try {
      final api = widget.api;
      final uri = Uri.parse('${api.baseUrl}/api/v1/beacon?token=${api.token}');
      final req = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream';
      _beaconClient = http.Client();
      final resp = await _beaconClient!.send(req);
      _logLine('Beacon: connected (${resp.statusCode})');
      resp.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
          (line) {
        if (!line.startsWith('data:')) return;
        try {
          final j = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
          if (j['itemId'] == widget.itemId) {
            _logLine('Beacon ← pos ${(j['positionSeconds'] as num).toStringAsFixed(0)}s '
                'from device ${j['originDeviceId']}');
          }
        } catch (_) {}
      });
    } catch (e) {
      _logLine('Beacon error: $e');
    }
  }

  void _reload() {
    _logLine('reload (ignoreResume=$_ignoreResume forceTranscode=$_forceTranscode)');
    _controller?.dispose();
    _controller = null;
    if (_transcodeSessionId != null) {
      widget.api.stopTranscode(_transcodeSessionId!);
      _transcodeSessionId = null;
    }
    _heartbeat?.cancel();
    _start();
  }

  Future<void> _enterPip() async {
    final supported =
        await _controller?.isPictureInPictureSupported() ?? false;
    _logLine('PiP supported: $supported');
    if (supported) await _controller?.enablePictureInPicture(_pipKey);
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _beaconClient?.close();
    _controller?.dispose();
    if (_transcodeSessionId != null) {
      widget.api.stopTranscode(_transcodeSessionId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: 'Picture-in-Picture',
              onPressed: _controller == null ? null : _enterPip,
              icon: const Icon(Icons.picture_in_picture_alt)),
          IconButton(
            tooltip: 'Restart from 0:00',
            onPressed: _controller == null
                ? null
                : () {
                    setState(() => _ignoreResume = true);
                    _reload();
                  },
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: _forceTranscode ? 'Forcing transcode' : 'Force transcode',
            onPressed: () {
              setState(() => _forceTranscode = !_forceTranscode);
              _reload();
            },
            icon: Icon(_forceTranscode ? Icons.hd : Icons.hd_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : BetterPlayer(key: _pipKey, controller: _controller!),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('debug log',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black87,
              width: double.infinity,
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(_log[i],
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
