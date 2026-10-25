import 'package:argosy/platform/pip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A replacement player registers before the outgoing one disposes, so the
/// outgoing one's teardown must not clear handlers it no longer owns
/// (ARGY-265).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> fire() async {
    await PiP.debugHandle(const MethodCall('pipChanged', true));
    await PiP.debugHandle(const MethodCall('pipAction', 'toggle'));
  }

  test('unregistering a superseded owner leaves the newer handlers', () async {
    final calls = <String>[];
    final a = PiP.register(
      onChanged: (_) => calls.add('a-changed'),
      onToggle: () => calls.add('a-toggle'),
    );
    final b = PiP.register(
      onChanged: (_) => calls.add('b-changed'),
      onToggle: () => calls.add('b-toggle'),
    );

    PiP.unregister(a);
    await fire();
    expect(calls, ['b-changed', 'b-toggle']);

    PiP.unregister(b);
    calls.clear();
    await fire();
    expect(calls, isEmpty);
  });

  test('unregistering twice is harmless', () async {
    var n = 0;
    final a = PiP.register(onToggle: () => n++);
    PiP.unregister(a);
    PiP.unregister(a);
    await fire();
    expect(n, 0);
  });
}
