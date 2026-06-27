import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_providers.dart';
import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_button.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../widgets/async_view.dart';
import '../playback_controller.dart';
import '../player_providers.dart';
import '../track_sheet.dart';

/// The 10-foot playback surface (ARGY-51 / `TVPlayer.dc.html`): the same
/// [PlaybackController] the phone player uses, behind a fully D-pad-driven
/// transport overlay. Arrows seek, OK plays/pauses, Down drops into the control
/// row (Next Episode / Subtitles / Audio / Speed / Fit), and the remote's BACK
/// pops back to the detail screen.
class TvPlayerScreen extends ConsumerWidget {
  const TvPlayerScreen({
    super.key,
    required this.itemId,
    this.resume = false,
    this.startOver = false,
  });

  final String itemId;
  final bool resume;
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
            _TvPlayerView(setup: data, resume: resume, startOver: startOver),
      ),
    );
  }
}

/// Which transport element the remote is "on". Focus here is drawn from state
/// (not Flutter's focus tree) so a single key handler owns the whole transport —
/// the most predictable model for a media remote.
enum _Row { seek, controls }

class _TvPlayerView extends ConsumerStatefulWidget {
  const _TvPlayerView({
    required this.setup,
    required this.resume,
    required this.startOver,
  });

  final PlayerSetup setup;
  final bool resume;
  final bool startOver;

  @override
  ConsumerState<_TvPlayerView> createState() => _TvPlayerViewState();
}

class _TvPlayerViewState extends ConsumerState<_TvPlayerView> {
  late final PlaybackController _controller;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv-player');

  /// Stable key for the [BetterPlayer] so its platform view (the video texture)
  /// persists across rebuilds.
  final GlobalKey _playerKey = GlobalKey();

  /// The video surface, built once and reused so the parent's frequent setState
  /// (the controls ticker, overlay show/hide, seek-bar position) never rebuilds
  /// it — rebuilding the platform view dropped the video while audio kept going.
  /// It still repaints on the controller's own notifications via the inner
  /// [AnimatedBuilder]; it just doesn't ride the parent's rebuilds.
  late final Widget _video = AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final player = _controller.player;
      if (player == null || !_controller.isReady) {
        return const ColoredBox(color: Colors.black);
      }
      return Center(child: BetterPlayer(key: _playerKey, controller: player));
    },
  );

  bool _overlayVisible = true;
  _Row _row = _Row.seek;
  int _controlIndex = 0;

  bool _showResumePrompt = false;
  double _resumePosition = 0;

  Timer? _hideTimer;
  Timer? _ticker;

  // Mirrors the phone player: set just before pushReplacement-ing into the next
  // episode so the outgoing dispose doesn't reset the immersive UI the incoming
  // player already armed. Static because it bridges two State objects.
  static bool _replacingWithPlayer = false;

  @override
  void initState() {
    super.initState();
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
    _controller.onAdvance = _advanceToNext;
    _controller.addListener(_onState);
    _beginPlayback();

    // Cheap repaint loop: keeps the scrub bar/clock live and drives the
    // credits-triggered roll-over (the controller has no progress event).
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      _controller.maybeAdvance();
      setState(() {});
    });
    _scheduleHide();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _advanceToNext() {
    final next = _controller.nextEpisode;
    if (!mounted || next == null) return;
    _replacingWithPlayer = true;
    context.pushReplacement('${Routes.player(next.id)}?resume=1');
  }

  void _beginPlayback() {
    final resumePos = _resumablePosition();
    if (resumePos != null && widget.resume) {
      _controller.start(resumePos);
    } else if (resumePos != null && !widget.startOver) {
      _resumePosition = resumePos;
      _showResumePrompt = true;
    } else {
      _controller.start(0);
    }
  }

  double? _resumablePosition() {
    final p = widget.setup.progress;
    final resumable = p != null && !p.watched && p.positionSeconds > 5;
    return resumable ? p.positionSeconds.toDouble() : null;
  }

  void _onResume() {
    setState(() => _showResumePrompt = false);
    _controller.start(_resumePosition);
    _rootFocus.requestFocus();
  }

  void _onStartOver() {
    setState(() => _showResumePrompt = false);
    _controller.start(0);
    _rootFocus.requestFocus();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ticker?.cancel();
    _controller.removeListener(_onState);
    _rootFocus.dispose();
    _controller.dispose();
    if (_replacingWithPlayer) {
      _replacingWithPlayer = false;
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // --- transport ------------------------------------------------------------

  void _showOverlay({_Row row = _Row.seek}) {
    setState(() {
      _overlayVisible = true;
      _row = row;
    });
    _scheduleHide();
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    setState(() => _overlayVisible = false);
    _rootFocus.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      // Only auto-hide once playback is actually running and the viewer is on
      // the seek bar (not paused, not still spinning up the transcode, not in
      // the control row). Otherwise keep checking — the first 4s can elapse
      // before playback begins, and we still want it to hide once it does.
      final canHide = _row == _Row.seek &&
          !_controller.starting &&
          (_controller.videoValue?.isPlaying ?? false);
      if (canHide) {
        setState(() => _overlayVisible = false);
        _rootFocus.requestFocus();
      } else if (_overlayVisible) {
        _scheduleHide();
      }
    });
  }

  void _seekBy(double delta) {
    _controller.seekTo(_controller.position + delta);
    _showOverlay();
  }

  List<_Control> get _controls {
    final c = _controller;
    return [
      if (c.nextEpisode != null)
        _Control('Next Episode', Icons.skip_next, c.playNext),
      _Control('Subtitles', Icons.closed_caption_outlined,
          () => _openTracks()),
      if (c.audioTracks.length > 1)
        _Control('Audio', Icons.graphic_eq, () => _openTracks()),
      _Control(c.fitLabel, Icons.aspect_ratio, () {
        c.cycleFit();
        _scheduleHide();
      }),
    ];
  }

  Future<void> _openTracks() async {
    _hideTimer?.cancel();
    await showTrackSheet(context, _controller);
    if (!mounted) return;
    _rootFocus.requestFocus(); // reclaim D-pad after the sheet closes
    _scheduleHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    bool isSelect() =>
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;

    // While hidden, any transport key just brings the overlay back.
    if (!_overlayVisible) {
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored; // let the route pop
      }
      _showOverlay();
      return KeyEventResult.handled;
    }

    if (_row == _Row.seek) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seekBy(-10);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _seekBy(10);
      } else if (isSelect()) {
        _controller.togglePlay();
        _showOverlay();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _row = _Row.controls;
          _controlIndex = 0;
        });
        _scheduleHide();
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _scheduleHide();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    // Control row.
    final controls = _controls;
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _controlIndex = (_controlIndex - 1).clamp(0, controls.length - 1));
      _scheduleHide();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _controlIndex = (_controlIndex + 1).clamp(0, controls.length - 1));
      _scheduleHide();
    } else if (isSelect()) {
      if (_controlIndex < controls.length) controls[_controlIndex].onSelect();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _row = _Row.seek);
      _scheduleHide();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _hideOverlay();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_showResumePrompt) {
      return _TvResumePrompt(
        title: widget.setup.item.title,
        position: _resumePosition,
        duration: widget.setup.item.durationSeconds?.toDouble() ?? 0,
        onResume: _onResume,
        onStartOver: _onStartOver,
      );
    }

    // Self-heal D-pad focus if it was lost — e.g. the route's modal scope
    // self-focused during the async setup load, or the track sheet popped. Route
    // the request through the scope (a plain requestFocus can't dislodge a scope
    // holding focus on itself), and never steal from a modal covering the player.
    if (!_rootFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_rootFocus.hasFocus &&
            ModalRoute.of(context)?.isCurrent == true) {
          FocusScope.of(context).requestFocus(_rootFocus);
        }
      });
    }

    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _video,
            if (_controller.fatalError)
              _ErrorOverlay(controller: _controller)
            else if (_overlayVisible)
              // Transparent stage so the video shows through behind the overlay
              // (its own scrims provide the dimming) — an opaque fill here is
              // what made the video "cut out" when the controls came up.
              TvStage(
                background: Colors.transparent,
                child: _Overlay(state: this),
              ),
            // When the overlay auto-hides we just show the video — no persistent
            // "press OK" hint (every media player has worked this way for years).
            // Up Next still surfaces near the end; the roll-over is automatic.
            _UpNextCard(controller: _controller),
          ],
        ),
      ),
    );
  }
}

class _Control {
  const _Control(this.label, this.icon, this.onSelect);
  final String label;
  final IconData icon;
  final VoidCallback onSelect;
}

/// The full transport overlay, authored at 1920×1080 inside [TvStage]: top bar,
/// center play-state, the focused seekbar, and the control row.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.state});

  final _TvPlayerViewState state;

  @override
  Widget build(BuildContext context) {
    final c = state._controller;
    final value = c.videoValue;
    final isPlaying = value?.isPlaying ?? false;
    final duration = c.catalogDuration;
    final pos = duration > 0 ? c.position.clamp(0.0, duration) : c.position;
    final seekFocused = state._row == _Row.seek;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Top + bottom scrims.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xDD0C0C0B), Colors.transparent, Color(0xF20C0C0B)],
              stops: [0, 0.42, 1],
            ),
          ),
        ),
        if (c.starting) const _Spinner(),

        // Top bar.
        Positioned(
          top: 54,
          left: 96,
          right: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chevron_left, size: 34, color: ArgosyColors.cream),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  formatTitle(state.widget.setup.item.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: ArgosyColors.cream,
                  ),
                ),
              ),
              if (c.qualityLabel != null) _QualityStamp(label: c.qualityLabel!),
            ],
          ),
        ),

        // Center play-state indicator (mirrors the remote: OK toggles).
        Align(
          alignment: const Alignment(0, -0.12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Glyph(icon: Icons.replay_10, label: '10s'),
              const SizedBox(width: 64),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x73141413),
                  border: Border.all(color: ArgosyColors.line3, width: 1.5),
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 46,
                  color: ArgosyColors.cream,
                ),
              ),
              const SizedBox(width: 64),
              const _Glyph(icon: Icons.forward_10, label: '10s'),
            ],
          ),
        ),

        // Bottom transport: hint, then seek bar, then control row.
        Positioned(
          left: 96,
          right: 96,
          bottom: 44,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('◂ ▸ to seek · OK to play / pause',
                        style: TextStyle(
                            fontFamily: 'HankenGrotesk',
                            fontSize: 14,
                            color: ArgosyColors.faint)),
                    Text('Down for controls',
                        style: TextStyle(
                            fontFamily: 'HankenGrotesk',
                            fontSize: 14,
                            color: ArgosyColors.faint)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SeekBar(
                position: pos.toDouble(),
                duration: duration,
                focused: seekFocused,
              ),
              const SizedBox(height: 18),
              _ControlRow(
                controls: state._controls,
                activeIndex: state._row == _Row.controls ? state._controlIndex : -1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.focused,
  });

  final double position;
  final double duration;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final pct = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: focused ? const Color(0x590C0C0B) : Colors.transparent,
        border: Border.all(
          color: focused ? ArgosyColors.accent : Colors.transparent,
          width: 3,
        ),
        boxShadow: focused
            ? const [BoxShadow(color: Color(0x24C99A4E), spreadRadius: 6)]
            : null,
      ),
      child: Row(
        children: [
          Text(
            formatClock(position),
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ArgosyColors.cream,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return SizedBox(
                  height: 26,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: ArgosyColors.line2,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      Container(
                        height: 8,
                        width: w * pct,
                        decoration: BoxDecoration(
                          color: ArgosyColors.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      Positioned(
                        left: (w * pct - 13).clamp(0.0, w - 26),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ArgosyColors.cream,
                            boxShadow: [
                              BoxShadow(
                                color: ArgosyColors.accent.withValues(alpha: 0.4),
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 22),
          Text(
            duration > 0 ? formatClock(duration) : '—',
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ArgosyColors.dim,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.controls, required this.activeIndex});

  final List<_Control> controls;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < controls.length; i++) ...[
          _ControlChip(control: controls[i], focused: i == activeIndex),
          if (i != controls.length - 1) const SizedBox(width: 14),
        ],
      ],
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({required this.control, required this.focused});

  final _Control control;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? 1.06 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? ArgosyColors.accent : const Color(0x99141413),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? Colors.transparent : ArgosyColors.line2,
            width: 1.5,
          ),
          boxShadow: focused
              ? const [BoxShadow(color: Color(0x24C99A4E), spreadRadius: 5)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(control.icon,
                size: 19,
                color: focused ? ArgosyColors.ink : ArgosyColors.soft2),
            const SizedBox(width: 9),
            Text(
              control.label,
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: focused ? ArgosyColors.ink : ArgosyColors.soft2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: ArgosyColors.soft2),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 15,
                color: ArgosyColors.soft2)),
      ],
    );
  }
}

/// Up Next card near the end of a series episode (mirrors the phone player).
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final next = c.nextEpisode;
    final duration = c.catalogDuration;
    if (next == null || !c.autoAdvance || c.upNextCancelled || duration <= 0) {
      return const SizedBox.shrink();
    }
    final remaining = duration - c.position;
    if (remaining > PlaybackController.upNextLeadSeconds || remaining <= 0) {
      return const SizedBox.shrink();
    }
    final countdown = (remaining - PlaybackController.upNextTailSeconds)
        .ceil()
        .clamp(
          1,
          PlaybackController.upNextLeadSeconds -
              PlaybackController.upNextTailSeconds,
        );
    final code = 'S${next.seasonNumber} E${next.episodeNumber}';
    final label = (next.title != null && next.title!.isNotEmpty)
        ? '$code · ${formatTitle(next.title!)}'
        : code;

    return Positioned(
      right: 40,
      bottom: 40,
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(
          color: const Color(0xF21A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ArgosyColors.accentLine),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UP NEXT',
                    style: TextStyle(
                        fontFamily: 'Archivo',
                        color: ArgosyColors.accent,
                        fontSize: 14,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700)),
                Text('in ${countdown}s',
                    style: const TextStyle(
                        color: ArgosyColors.dim, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: ArgosyColors.cream,
                    fontSize: 19,
                    fontFamily: 'Archivo',
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Resume / Start-over chooser (D-pad), shown when there's saved progress and
/// the entry point didn't pre-decide.
class _TvResumePrompt extends StatelessWidget {
  const _TvResumePrompt({
    required this.title,
    required this.position,
    required this.duration,
    required this.onResume,
    required this.onStartOver,
  });

  final String title;
  final double position;
  final double duration;
  final VoidCallback onResume;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final remaining = (duration - position).clamp(0, duration > 0 ? duration : position);
    return ColoredBox(
      color: const Color(0xF0000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CROSS-DEVICE RESUME',
              style: TextStyle(
                fontFamily: 'Archivo',
                color: ArgosyColors.accent,
                fontSize: 16,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Pick up where you left off?',
              style: const TextStyle(
                fontFamily: 'Archivo',
                color: ArgosyColors.cream,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${formatTitle(title)} · ${formatClock(remaining)} remaining',
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                color: ArgosyColors.soft,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvButton(
                  label: 'Resume from ${formatClock(position)}',
                  icon: Icons.play_arrow,
                  primary: true,
                  autofocus: true,
                  onSelect: onResume,
                ),
                const SizedBox(width: 16),
                TvButton(
                  label: 'Start from the beginning',
                  icon: Icons.replay,
                  onSelect: onStartOver,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityStamp extends StatelessWidget {
  const _QualityStamp({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: ArgosyColors.accentBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArgosyColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Archivo',
          color: ArgosyColors.accent,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: ArgosyColors.accent),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: ArgosyColors.danger),
          const SizedBox(height: 18),
          Text(
            controller.errorMessage ?? 'This title could not be played.',
            style: const TextStyle(color: ArgosyColors.cream, fontSize: 20),
          ),
          const SizedBox(height: 22),
          TvButton(
            label: 'Retry',
            primary: true,
            autofocus: true,
            onSelect: controller.retry,
          ),
        ],
      ),
    );
  }
}
