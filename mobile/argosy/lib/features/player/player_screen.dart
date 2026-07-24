import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_providers.dart';
import '../../api/artwork.dart';
import '../../platform/pip.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/button_styles.dart';
import '../../util/format.dart';
import '../../widgets/async_view.dart';
import 'playback_controller.dart';
import 'player_controls.dart';
import 'player_providers.dart';

/// The full playback surface (ARGY-79): direct play or HLS transcode, an Argosy
/// controls overlay, subtitle/audio track selection, resume, and progress
/// reporting. Built on the player proven in the ARGY-77 spike.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    this.resume = false,
    this.startOver = false,
  });

  final String itemId;

  /// Resume straight from the saved position without asking.
  final bool resume;

  /// Force playback from the top without asking.
  final bool startOver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(playerSetupProvider(itemId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: AsyncView(
        value: setup,
        onRetry: () => ref.invalidate(playerSetupProvider(itemId)),
        builder: (data) =>
            _PlayerView(setup: data, resume: resume, startOver: startOver),
      ),
    );
  }
}

class _PlayerView extends ConsumerStatefulWidget {
  const _PlayerView({
    required this.setup,
    required this.resume,
    required this.startOver,
  });

  final PlayerSetup setup;
  final bool resume;
  final bool startOver;

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

  // Set just before we pushReplacement one player with the next episode's player
  // (auto-advance). The outgoing screen's dispose runs *after* the incoming
  // screen's initState, so without this guard dispose would reset orientation /
  // UI mode and clobber the new player's landscape + immersive lock — leaving the
  // next episode stuck in portrait. Static because it bridges two State objects.
  static bool _replacingWithPlayer = false;

  // Resume-vs-start-over prompt (web parity): shown when there's saved progress
  // and the entry point didn't explicitly choose. Playback is deferred until
  // the user picks.
  bool _showResumePrompt = false;
  double _resumePosition = 0;

  /// Now-playing header: for a series episode with resolved metadata this reads
  /// "Show · Episode Title · Season 1, Ep 1"; films and un-matched episodes fall
  /// back to the humanized flat title (ARGY-134).
  String get _headerTitle {
    final it = widget.setup.item;
    if (it.seriesTitle != null &&
        it.seasonNumber != null &&
        it.episodeNumber != null) {
      return episodeHeader(
        it.seriesTitle!,
        episodeName(it.episodeTitle),
        it.seasonNumber!,
        it.episodeNumber!,
      );
    }
    return formatTitle(it.title);
  }

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
      preferredLanguages: setup.preferredLanguages,
      prefs: setup.prefs,
    );
    _controller.onAdvance = _advanceToNext;
    _beginPlayback();
    _setupPip();
  }

  /// Series auto-advance (ARGY-93): roll into the next episode, resuming from its
  /// own saved position (or the top). pushReplacement so Back doesn't return to
  /// the finished episode — the new player fully remounts (clean teardown).
  void _advanceToNext() {
    final next = _controller.nextEpisode;
    if (!mounted || next == null) return;
    _replacingWithPlayer = true;
    context.pushReplacement('${Routes.player(next.id)}?resume=1');
  }

  /// Mirrors the web entry-point logic: `resume` jumps straight to the saved
  /// position, `startOver` forces the top, and a bare open *asks* (the resume
  /// prompt) when there's history — otherwise it just starts from the top.
  void _beginPlayback() {
    final resumePos = _resumablePosition();
    if (resumePos != null && widget.resume) {
      _startAt(resumePos);
    } else if (resumePos != null && !widget.startOver) {
      setState(() {
        _resumePosition = resumePos;
        _showResumePrompt = true;
      });
    } else {
      _startAt(0);
    }
  }

  /// Starts playback and arms auto-enter PiP. Deferred until real playback (not
  /// during the resume prompt) so backgrounding the chooser doesn't float a
  /// black window.
  void _startAt(double offset) {
    _controller.start(offset);
    PiP.setActive(true);
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
    // Keep the PiP play/pause action icon in sync with playback. (Auto-enter is
    // armed by _startAt once real playback begins, not here.)
    _controller.addListener(_syncPipPlaying);
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

  /// The saved position to resume from, or null when there's nothing resumable
  /// (no history, already watched, or barely started).
  double? _resumablePosition() {
    final p = widget.setup.progress;
    final resumable = p != null && !p.watched && p.positionSeconds > 5;
    return resumable ? p.positionSeconds.toDouble() : null;
  }

  void _onResume() {
    final pos = _resumePosition;
    setState(() => _showResumePrompt = false);
    _startAt(pos);
  }

  void _onStartOver() {
    setState(() => _showResumePrompt = false);
    _startAt(0);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncPipPlaying);
    PiP.register();
    PiP.setActive(false);
    _controller.dispose();
    // When replacing this player with the next episode's player, the incoming
    // screen has already locked landscape + immersive in its initState; resetting
    // here (dispose runs afterwards) would knock the next episode into portrait.
    // Only restore the app's default chrome when truly leaving the player.
    if (_replacingWithPlayer) {
      _replacingWithPlayer = false;
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
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
          // The resume prompt also owns the screen until the user chooses.
          if (!_inPip && !_showResumePrompt)
            PlayerControls(
              controller: _controller,
              title: _headerTitle,
              onBack: () => Navigator.of(context).maybePop(),
              onEnterPip: _pipSupported ? _enterPip : null,
            ),
          if (_showResumePrompt && !_inPip)
            _ResumePrompt(
              title: widget.setup.item.title,
              position: _resumePosition,
              duration: widget.setup.item.durationSeconds?.toDouble() ?? 0,
              onResume: _onResume,
              onStartOver: _onStartOver,
              onBack: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}

/// The Resume / Start-over chooser shown over a black backdrop when a title has
/// saved progress and the entry point didn't pre-decide — mirrors the web
/// player's resume card, down to the brass glow on the primary button.
class _ResumePrompt extends StatefulWidget {
  const _ResumePrompt({
    required this.title,
    required this.position,
    required this.duration,
    required this.onResume,
    required this.onStartOver,
    required this.onBack,
  });

  final String title;
  final double position;
  final double duration;
  final VoidCallback onResume;
  final VoidCallback onStartOver;
  final VoidCallback onBack;

  @override
  State<_ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends State<_ResumePrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.duration - widget.position)
        .clamp(0, widget.duration > 0 ? widget.duration : widget.position);
    return ColoredBox(
      color: const Color(0xE6000000),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, color: ArgosyColors.cream),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CROSS-DEVICE RESUME',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ArgosyColors.accent,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pick up where you left off?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${formatTitle(widget.title)} · ${formatClock(remaining)} remaining',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: ArgosyColors.soft),
                      ),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: _glow,
                        builder: (context, child) {
                          final t = _glow.value;
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: ArgosyColors.accent
                                      .withValues(alpha: 0.45 + 0.27 * t),
                                  blurRadius: 16 + 14 * t,
                                  spreadRadius: 1 + 4 * t,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: brassButtonStyle(context),
                            onPressed: widget.onResume,
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: Text(
                                'Resume from ${formatClock(widget.position)}'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: ghostButtonStyle(context),
                          onPressed: widget.onStartOver,
                          icon: const Icon(Icons.replay, size: 18),
                          label: const Text('Start from the beginning'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
