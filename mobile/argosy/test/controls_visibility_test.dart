import 'package:argosy/features/player/controls_visibility.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone overlay's auto-hide (ARGY-280). The old overlay armed one timer
/// at mount; when it fired during the transcode's start-up there was nothing
/// playing to hide and it was never re-armed, so the controls sat on screen
/// until a tap. These pin the rule the notifier now owns: fade [hideAfter]
/// after the last interaction, only while playing; never while paused; the
/// countdown restarts on a tap or a seek.
final _hideAfter = ControlsVisibility().hideAfter;
const _tick = Duration(milliseconds: 100);

void main() {
  ControlsVisibility make() => ControlsVisibility();

  test('the default fade is about three seconds', () {
    expect(_hideAfter, const Duration(milliseconds: 3500));
  });

  test('controls show at start and fade once playback is actually running', () {
    fakeAsync((async) {
      final v = make();
      expect(v.visible, isTrue);

      // Transcode spin-up: the old 3.5s timer would have fired here, found
      // nothing playing, and given up for good.
      async.elapse(const Duration(seconds: 10));
      expect(v.visible, isTrue, reason: 'nothing to hide before playback');
      expect(v.armed, isFalse);

      v.setCanHide(true); // first `play` event
      expect(v.armed, isTrue, reason: 'playback starting must arm the hide');
      async.elapse(_hideAfter - _tick);
      expect(v.visible, isTrue);
      async.elapse(_tick);
      expect(v.visible, isFalse, reason: 'no interaction for 3.5s → hidden');
    });
  });

  test('a tap brings them back and they fade again on their own', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      async.elapse(_hideAfter);
      expect(v.visible, isFalse);

      v.toggle(); // tap the bare video
      expect(v.visible, isTrue);
      async.elapse(_hideAfter - _tick);
      expect(v.visible, isTrue);
      async.elapse(_tick);
      expect(v.visible, isFalse);

      // Tapping while visible dismisses immediately.
      v.toggle();
      expect(v.visible, isTrue);
      v.toggle();
      expect(v.visible, isFalse);
      expect(v.armed, isFalse);
    });
  });

  test('they stay while paused, and hide again after unpause', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      async.elapse(const Duration(seconds: 1));

      v.touch(); // the pause button
      v.setCanHide(false); // `pause` event
      expect(v.armed, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(v.visible, isTrue, reason: 'paused controls never fade');

      // Resume from anywhere — the on-screen button, the media session, PiP:
      // the controller's `play` event alone must restart the countdown.
      v.setCanHide(true);
      async.elapse(_hideAfter - _tick);
      expect(v.visible, isTrue);
      async.elapse(_tick);
      expect(v.visible, isFalse);
    });
  });

  test('buffering with the controls up does not count down', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      async.elapse(const Duration(seconds: 2));
      v.setCanHide(false); // stalled: isPlaying false
      async.elapse(const Duration(seconds: 30));
      expect(v.visible, isTrue);
      v.setCanHide(true);
      async.elapse(_hideAfter);
      expect(v.visible, isFalse);
    });
  });

  test('a seek re-arms the countdown from scratch', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      async.elapse(const Duration(seconds: 3)); // 0.5s from hiding

      v.touch(); // ±10s or a scrub release
      async.elapse(const Duration(seconds: 3));
      expect(v.visible, isTrue, reason: 'the seek restarted the 3.5s');
      async.elapse(const Duration(milliseconds: 500));
      expect(v.visible, isFalse);
    });
  });

  test('a scrub in progress holds the controls until it is released', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      v.hold(); // finger down on the slider
      async.elapse(const Duration(seconds: 20));
      expect(v.visible, isTrue);
      expect(v.armed, isFalse);

      v.touch(); // released: seek issued
      async.elapse(_hideAfter);
      expect(v.visible, isFalse);
    });
  });

  test('a seek while hidden shows the controls first', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      async.elapse(_hideAfter);
      expect(v.visible, isFalse);
      v.touch();
      expect(v.visible, isTrue);
      async.elapse(_hideAfter);
      expect(v.visible, isFalse);
    });
  });

  test('repeated state updates do not keep pushing the hide back', () {
    fakeAsync((async) {
      // The controller notifies and the repaint loop ticks continuously; a
      // playing→playing update must not restart the countdown.
      final v = make()..setCanHide(true);
      for (var i = 0; i < 40; i++) {
        async.elapse(_tick);
        v.setCanHide(true);
      }
      expect(v.visible, isFalse, reason: '4s of no-op updates must still hide');
    });
  });

  test('listeners are told on every change', () {
    fakeAsync((async) {
      final v = make()..setCanHide(true);
      var n = 0;
      v.addListener(() => n++);
      async.elapse(_hideAfter);
      expect(n, 1); // auto-hide
      v.toggle();
      expect(n, 2); // tap shows
      v.touch();
      expect(n, 2, reason: 'touch while visible is not a visibility change');
      async.elapse(_hideAfter);
      expect(n, 3);
    });
  });
}
