import 'dart:async';

import 'package:flutter/foundation.dart';

/// Owns the phone overlay's show/hide state and its auto-hide timer
/// (ARGY-280), apart from the widget so it can run under a fake clock.
///
/// The rule: the controls fade [hideAfter] after the last interaction, but only
/// while playback is actually running. Before this class, the overlay armed a
/// single one-shot timer when it mounted; if that fired while the transcode
/// was still starting (or before the first `play` event) it found nothing to
/// hide and nobody re-armed it, so the controls stayed up until a tap.
///
/// The owner feeds in [setCanHide] (playing, not starting, no fatal error) on
/// every controller update; the timer is armed only while that holds and is
/// cancelled when it stops, so a paused or buffering player keeps its controls.
class ControlsVisibility extends ChangeNotifier {
  ControlsVisibility({this.hideAfter = const Duration(milliseconds: 3500)});

  final Duration hideAfter;

  bool _visible = true;
  bool _canHide = false;
  bool _held = false;
  Timer? _timer;

  bool get visible => _visible;

  /// Whether an auto-hide is currently pending.
  @visibleForTesting
  bool get armed => _timer?.isActive ?? false;

  /// Playback state gate: true while the player is playing, past `starting`,
  /// and not in a fatal error. Flipping it true (re)arms the hide if the
  /// controls are showing; flipping it false cancels any pending hide. A
  /// repeat of the current value is a no-op, so continuous controller
  /// updates and repaint ticks never push the countdown back.
  void setCanHide(bool value) {
    if (value == _canHide) return;
    _canHide = value;
    if (value) {
      _arm();
    } else {
      _cancel();
    }
  }

  /// A tap on the bare video: toggles, and arms the hide when showing.
  void toggle() {
    _visible = !_visible;
    if (_visible) {
      _arm();
    } else {
      _cancel();
    }
    notifyListeners();
  }

  /// Any interaction with a control (play/pause, a seek, a dismissed sheet):
  /// keeps the controls showing and restarts the countdown.
  void touch() {
    _held = false;
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
    _arm();
  }

  /// Suspends the countdown while something has the viewer's attention — a
  /// scrub drag or an open track sheet. [touch] releases it.
  void hold() {
    _held = true;
    _cancel();
  }

  void _arm() {
    _cancel();
    if (!_canHide || !_visible || _held) return;
    _timer = Timer(hideAfter, () {
      _timer = null;
      if (!_canHide || !_visible || _held) return;
      _visible = false;
      notifyListeners();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
