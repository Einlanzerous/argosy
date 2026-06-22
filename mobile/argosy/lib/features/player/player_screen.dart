import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../api/artwork.dart';
import '../../platform/pip.dart';
import '../../widgets/async_view.dart';
import 'playback_controller.dart';
import 'player_controls.dart';
import 'player_providers.dart';

/// The full playback surface (ARGY-79): direct play or HLS transcode, an Argosy
/// controls overlay, subtitle/audio track selection, resume, and progress
/// reporting. Built on the player proven in the ARGY-77 spike.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.itemId, this.resume = false});

  final String itemId;
  final bool resume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(playerSetupProvider(itemId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: AsyncView(
        value: setup,
        onRetry: () => ref.invalidate(playerSetupProvider(itemId)),
        builder: (data) => _PlayerView(setup: data, resume: resume),
      ),
    );
  }
}

class _PlayerView extends ConsumerStatefulWidget {
  const _PlayerView({required this.setup, required this.resume});

  final PlayerSetup setup;
  final bool resume;

  @override
  ConsumerState<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<_PlayerView> {
  late final PlaybackController _controller;

  /// Attached to the [BetterPlayer] widget so better_player_plus can locate the
  /// video's render box for iOS AVKit PiP.
  final GlobalKey _playerKey = GlobalKey();

  bool _pipSupported = false;
  bool _inPip = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final setup = widget.setup;
    _controller = PlaybackController(
      libraryApi: ref.read(libraryApiProvider),
      transcodeApi: ref.read(transcodeApiProvider),
      authApi: ref.read(authApiProvider),
      baseUrl: ref.read(baseUrlProvider),
      token: ref.read(tokenStoreProvider).token,
      itemId: setup.item.id,
      title: setup.item.title,
      notificationAuthor: setup.item.year?.toString(),
      artworkUrl: ref.read(artworkResolverProvider)(
        setup.item.posterUrl ?? setup.item.backdropUrl,
      ),
      catalogDuration: setup.item.durationSeconds?.toDouble() ?? 0,
      isTranscode: setup.isTranscode,
      hevc: setup.hevc,
      subtitles: setup.subtitles,
      prefs: setup.prefs,
    );
    _controller.start(_startOffset());
    _setupPip();
  }

  /// Enables auto-enter-on-leave PiP (Android) and tracks PiP mode so the
  /// overlay can hide its chrome while floating (ARGY-50). On iOS, PiP is
  /// AVKit-driven by better_player_plus, so the button is always offered and
  /// the system supplies its own PiP overlay.
  Future<void> _setupPip() async {
    if (Platform.isIOS) {
      setState(() => _pipSupported = true);
      return;
    }
    final supported = await PiP.isSupported();
    if (!mounted) return;
    setState(() => _pipSupported = supported);
    if (!supported) return;
    PiP.register(
      onChanged: (inPip) {
        if (mounted) setState(() => _inPip = inPip);
      },
      onToggle: () => _controller.togglePlay(),
    );
    // Keep the PiP play/pause action icon in sync with playback.
    _controller.addListener(_syncPipPlaying);
    await PiP.setActive(true);
  }

  bool? _lastPipPlaying;

  void _syncPipPlaying() {
    final playing = _controller.videoValue?.isPlaying ?? false;
    if (playing != _lastPipPlaying) {
      _lastPipPlaying = playing;
      PiP.setPlaying(playing);
    }
  }

  /// Enters PiP: native on Android, AVKit (via better_player_plus) on iOS.
  Future<void> _enterPip() async {
    if (Platform.isIOS) {
      await _controller.player?.enablePictureInPicture(_playerKey);
    } else {
      await PiP.enter();
    }
  }

  /// Resume from the saved position only when the entry point asked to (the
  /// detail screen offers Resume vs. Start over); otherwise start at 0.
  double _startOffset() {
    final p = widget.setup.progress;
    final resumable = p != null && !p.watched && p.positionSeconds > 5;
    return (widget.resume && resumable) ? p.positionSeconds.toDouble() : 0;
  }

  @override
  void dispose() {
    _controller.removeListener(_syncPipPlaying);
    PiP.register();
    PiP.setActive(false);
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final player = _controller.player;
              if (player == null || !_controller.isReady) {
                return const ColoredBox(color: Colors.black);
              }
              return Center(child: BetterPlayer(key: _playerKey, controller: player));
            },
          ),
          // In PiP the system window shows only the video — suppress all chrome.
          if (!_inPip)
            PlayerControls(
              controller: _controller,
              title: widget.setup.item.title,
              onBack: () => Navigator.of(context).maybePop(),
              onEnterPip: _pipSupported ? _enterPip : null,
            ),
        ],
      ),
    );
  }
}
