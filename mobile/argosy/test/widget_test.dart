// Smoke test for the app shell: the auth gate should boot on the splash and,
// once bootstrap resolves to unauthenticated, redirect to the login screen.

import 'package:argosy/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots on splash then redirects to login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ArgosyApp()));

    // Splash shows the wordmark while auth bootstraps.
    expect(find.text('ARGOSY'), findsOneWidget);

    // Let the bootstrap delay elapse + the redirect settle.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Welcome aboard'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
