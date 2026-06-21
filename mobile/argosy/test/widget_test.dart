// Smoke test for the app shell: the auth gate should boot on the splash and,
// once bootstrap resolves to unauthenticated, redirect to the login screen.

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/api/token_store.dart';
import 'package:argosy/app.dart';
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
        overrides: [tokenStoreProvider.overrideWithValue(_FakeTokenStore())],
        child: const ArgosyApp(),
      ),
    );

    // Splash shows the wordmark while auth bootstraps.
    expect(find.text('ARGOSY'), findsOneWidget);

    // Let the redirect settle.
    await tester.pumpAndSettle();

    // Pairing flow opens on the server-address step.
    expect(find.text('Connect to your server'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
