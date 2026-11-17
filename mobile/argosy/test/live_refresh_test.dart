// When the app refetches progress made on another device (ARGY-291): debounced
// on Beacon events, throttled on app resume and on stream reconnect, mirroring
// web's liveProgress (ARGY-290).

import 'package:argosy/features/beacon/live_refresh.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int refreshes;
  LiveRefresh make(FakeAsync async) {
    refreshes = 0;
    return LiveRefresh(
      refresh: () => refreshes++,
      now: () => DateTime(2026).add(async.elapsed),
    );
  }

  test('a burst of foreign events collapses to one trailing refetch', () {
    fakeAsync((async) {
      final live = make(async);
      for (var i = 0; i < 5; i++) {
        live.onForeignEvent();
        async.elapse(const Duration(milliseconds: 500));
      }
      expect(refreshes, 0); // still inside the debounce window
      async.elapse(const Duration(milliseconds: 1500));
      expect(refreshes, 1);
    });
  });

  test('resume refetches at once, but not twice within the throttle', () {
    fakeAsync((async) {
      final live = make(async);
      live.onResumed();
      expect(refreshes, 1);
      async.elapse(const Duration(seconds: 2));
      live.onResumed();
      expect(refreshes, 1);
      async.elapse(const Duration(seconds: 4));
      live.onResumed();
      expect(refreshes, 2);
    });
  });

  test('the first stream open is the initial connect; reconnects refetch', () {
    fakeAsync((async) {
      final live = make(async);
      live.onStreamOpened();
      expect(refreshes, 0);
      live.onStreamOpened();
      expect(refreshes, 1);
    });
  });

  test('a throttled refetch absorbs a pending debounced one', () {
    fakeAsync((async) {
      final live = make(async);
      live.onForeignEvent();
      live.onResumed();
      expect(refreshes, 1);
      async.elapse(const Duration(seconds: 3));
      expect(refreshes, 1);
    });
  });

  test('nothing fires after dispose', () {
    fakeAsync((async) {
      final live = make(async);
      live.onForeignEvent();
      live.dispose();
      async.elapse(const Duration(seconds: 3));
      live.onResumed();
      expect(refreshes, 0);
    });
  });
}
