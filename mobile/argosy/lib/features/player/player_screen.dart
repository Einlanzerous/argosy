import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
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
      catalogDuration: setup.item.durationSeconds?.toDouble() ?? 0,
      isTranscode: setup.isTranscode,
      hevc: setup.hevc,
      subtitles: setup.subtitles,
      prefs: setup.prefs,
    );
    _controller.start(_startOffset());
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
              if (player == null || !(player.isVideoInitialized() ?? false)) {
                return const ColoredBox(color: Colors.black);
              }
              return Center(child: BetterPlayer(controller: player));
            },
          ),
          PlayerControls(
            controller: _controller,
            title: widget.setup.item.title,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
