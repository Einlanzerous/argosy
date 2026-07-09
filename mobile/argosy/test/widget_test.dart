// Smoke test for the app shell: the auth gate should boot on the splash and,
// once bootstrap resolves to unauthenticated, redirect to the login screen.

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/api/token_store.dart';
import 'package:argosy/app.dart';
import 'package:argosy/platform/device_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory store so the test never touches the platform secure-storage plugin.
class _FakeTokenStore extends TokenStore {
  _FakeTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<void> load() async {}
}

void main() {
  testWidgets('boots on splash then redirects to login', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
          // Pin the touch shell; `main()` injects this in the real app (ARGY-51).
          isTelevisionProvider.overrideWithValue(false),
        ],
        child: const ArgosyApp(),
      ),
    );

    // Splash shows the wordmark while auth bootstraps.
    expect(find.text('ARGOSY'), findsOneWidget);

    // Let the redirect + the PIN controller's discovery attempt settle
    // (bounded pumps — the code step animates a spinner while searching, so
    // pumpAndSettle would never return). Advancing past the discovery
    // timeout + hang backstop lands the fallback offer regardless of how the
    // absent mDNS plugin fails (throw, silence, or hang).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 9));

    // PIN-first (ARGY-123): the pairing flow opens on the code step. With no
    // discovery plugin in the test env the search fails fast into the
    // graceful fallback offer.
    expect(find.text("Can't find your server"), findsOneWidget);

    // The manual server-address fallback is still a tap away.
    await tester.tap(find.text('Enter address manually'));
    await tester.pump();
    expect(find.text('Connect to your server'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
