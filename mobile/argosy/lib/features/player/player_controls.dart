import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/argosy_colors.dart';
import '../../util/format.dart';
import 'controls_visibility.dart';
import 'playback_controller.dart';
import 'track_sheet.dart';

/// The Argosy-styled transport overlay that replaces better_player_plus's
/// built-in UI (ARGY-79). It scrubs over the *catalog* duration — the true
/// runtime — rather than the growing HLS playlist, and routes every seek through
/// [PlaybackController.seekTo] so transcode restarts happen transparently.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.title,
    required this.onBack,
    this.onEnterPip,
  });

  final PlaybackController controller;
  final String title;
  final VoidCallback onBack;

  /// Enters Picture-in-Picture; null when PiP is unsupported (the button is then
  /// hidden). See ARGY-50.
  final Future<void> Function()? onEnterPip;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  // Show/hide state and the auto-hide countdown live in a notifier (ARGY-280)
  // so the timer is gated on real playback rather than fired once at mount:
  // the old one-shot timer usually went off while the transcode was still
  // starting, found nothing to hide, and was never re-armed.
  final ControlsVisibility _vis = ControlsVisibility();
  double? _dragValue;
  Timer? _ticker;

  PlaybackController get _c => widget.controller;
  bool get _visible => _vis.visible;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onState);
    _vis.addListener(_onState);
    // Cheap repaint loop so the scrub bar + clock track playback smoothly and
    // the buffering spinner stays live even while the controls are hidden.
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      // Credits-triggered roll-over (ARGY-90): the controller has no progress
      // event, so the repaint loop is also where we check for the early advance.
      _c.maybeAdvance();
      _syncCanHide();
      setState(() {});
    });
    _syncCanHide();
  }

  @override
  void dispose() {
    _c.removeListener(_onState);
    _vis.removeListener(_onState);
    _vis.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    _syncCanHide();
    setState(() {});
  }

  /// The controls may only fade while the video is really playing: not while
  /// the transcode is starting, not paused, not on the error overlay. Fed on
  /// every controller update and every repaint tick (a repeat is a no-op in
  /// the notifier), so the countdown arms the moment playback begins and is
  /// dropped the moment it pauses — however the pause or resume was driven.
  void _syncCanHide() {
    final playing = _c.videoValue?.isPlaying ?? false;
    _vis.setCanHide(playing && !_c.starting && !_c.fatalError);
  }

  void _toggle() => _vis.toggle();

  /// An interaction with a control: keep the overlay up and restart the fade.
  void _scheduleHide() => _vis.touch();

  @override
  Widget build(BuildContext context) {
    if (_c.fatalError) return _ErrorOverlay(controller: _c);

    final value = _c.videoValue;
    final isPlaying = value?.isPlaying ?? false;
    final isBuffering = (value?.isBuffering ?? false) && !_c.starting;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Loading/buffering indicators sit above the (dimmed) video.
          if (_c.starting)
            const _Spinner(label: 'Starting…')
          else if (isBuffering)
            const _Spinner(),

          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_visible,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000), Color(0xCC000000)],
                    stops: [0, 0.4, 1],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _topBar(context),
                      Expanded(
                        child: _c.starting
                            ? const SizedBox.shrink()
                            : _centerControls(isPlaying),
                      ),
                      _bottomBar(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Up Next sits outside the fade so it stays put (and tappable) once the
          // controls hide near the end of an episode.
          _upNextCard(context),
        ],
      ),
    );
  }

  /// The Up Next card (ARGY-93): appears in the last [PlaybackController
  /// .upNextLeadSeconds] of a series episode when auto-advance is on and a next
  /// episode exists. Visibility and countdown both come from the controller,
  /// which owns the one timer — deriving the countdown here from the playhead is
  /// what made seeking into the window hand out a truncated one (ARGY-207).
  Widget _upNextCard(BuildContext context) {
    final next = _c.nextEpisode;
    if (next == null || !_c.upNextOpen) return const SizedBox.shrink();
    final countdown = _c.upNextCountdown;
    final code = 'S${next.seasonNumber} E${next.episodeNumber}';
    final label = (next.title != null && next.title!.isNotEmpty)
        ? '$code · ${formatTitle(next.title!)}'
        : code;

    return Positioned(
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: const Color(0xF21A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ArgosyColors.accent.withValues(alpha: 0.32)),
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
                        color: ArgosyColors.accent,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      )),
                  if (!_c.upNextHeld)
                    Text('in ${countdown}s',
                        style: const TextStyle(
                            color: ArgosyColors.dim, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ArgosyColors.cream,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _c.playNext,
                      style: FilledButton.styleFrom(
                        backgroundColor: ArgosyColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text('Play Next'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      _c.cancelUpNext();
                      _scheduleHide();
                    },
                    child: const Text('Cancel',
                        style: TextStyle(color: ArgosyColors.soft)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, color: ArgosyColors.cream),
          ),
          Expanded(
            child: Text(
              formatTitle(widget.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: ArgosyColors.cream),
            ),
          ),
          if (_c.qualityLabel != null) _QualityStamp(label: _c.qualityLabel!),
          if (widget.onEnterPip != null)
            IconButton(
              tooltip: 'Picture-in-picture',
              onPressed: () => widget.onEnterPip!(),
              icon: const Icon(Icons.picture_in_picture_alt,
                  color: ArgosyColors.cream),
            ),
        ],
      ),
    );
  }

  Widget _centerControls(bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.replay_10,
          size: 34,
          onPressed: () => _seekBy(-10),
        ),
        const SizedBox(width: 36),
        _RoundButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: 52,
          onPressed: () {
            _c.togglePlay();
            _scheduleHide();
          },
        ),
        const SizedBox(width: 36),
        _RoundButton(
          icon: Icons.forward_10,
          size: 34,
          onPressed: () => _seekBy(10),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    final duration = _c.catalogDuration;
    final pos = _dragValue ?? _c.position;
    final clamped = duration > 0 ? pos.clamp(0.0, duration) : pos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(formatClock(clamped),
                  style: const TextStyle(color: ArgosyColors.cream, fontSize: 13)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: ArgosyColors.accent,
                    inactiveTrackColor: ArgosyColors.line2,
                    thumbColor: ArgosyColors.accentHi,
                    overlayColor: ArgosyColors.accentBg2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: clamped.toDouble(),
                    max: duration > 0 ? duration : 1,
                    onChanged: duration > 0
                        ? (v) {
                            setState(() => _dragValue = v);
                            _vis.hold();
                          }
                        : null,
                    onChangeEnd: duration > 0
                        ? (v) {
                            _c.seekTo(v);
                            setState(() => _dragValue = null);
                            _scheduleHide();
                          }
                        : null,
                  ),
                ),
              ),
              Text(
                duration > 0 ? '-${formatClock(duration - clamped)}' : '—',
                style: const TextStyle(color: ArgosyColors.soft, fontSize: 13),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_c.audioTracks.length > 1)
                  IconButton(
                    tooltip: 'Audio',
                    onPressed: () => _openTracks(TrackKind.audio),
                    icon: const Icon(Icons.graphic_eq,
                        color: ArgosyColors.cream),
                  ),
                IconButton(
                  tooltip: 'Subtitles',
                  onPressed: () => _openTracks(TrackKind.subtitles),
                  icon: const Icon(Icons.closed_caption_outlined,
                      color: ArgosyColors.cream),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openTracks(TrackKind kind) {
    _vis.hold();
    showTrackSheet(context, _c, kind).then((_) => _scheduleHide());
  }

  void _seekBy(double delta) {
    _c.seekTo(_c.position + delta);
    _scheduleHide();
  }
}

/// Brass quality pill ("4K" / "1080p"), matching the web player's `.quality`
/// badge in the top-right chrome.
class _QualityStamp extends StatelessWidget {
  const _QualityStamp({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ArgosyColors.accentBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArgosyColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ArgosyColors.accent,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      iconSize: size,
      color: ArgosyColors.cream,
      icon: Icon(icon),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: ArgosyColors.accent),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!,
                style: const TextStyle(color: ArgosyColors.soft, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: ArgosyColors.danger),
            const SizedBox(height: 16),
            Text(
              controller.errorMessage ?? 'This title could not be played.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArgosyColors.cream),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: controller.retry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
