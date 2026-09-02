import 'package:argosy/api/api_providers.dart';
import 'package:argosy/api/token_store.dart';
import 'package:argosy/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory store so the test never touches the platform secure-storage
/// plugin, and so what got persisted is observable.
class _FakeTokenStore extends TokenStore {
  _FakeTokenStore() : super(const FlutterSecureStorage());

  String? savedBaseUrl;

  @override
  Future<void> load() async {}

  @override
  Future<void> setBaseUrl(String? url) async => savedBaseUrl = url;
}

/// Manual server entry used to prepend `http://` to any bare hostname, which
/// aims at plain HTTP on port 80. The public edge answers only on 443, so a
/// typed `argosy.zerogravity.industries` failed outright — an eight-second
/// spinner and a generic network error with nothing pointing at the scheme
/// (ARGY-192). A bare host is now probed HTTPS-first, and falls back to
/// cleartext only where cleartext can't reach the open internet.
void main() {
  group('serverUrlCandidates', () {
    test('an explicit scheme is honoured as typed, never second-guessed', () {
      expect(AuthController.serverUrlCandidates('http://10.0.0.20:8097'), [
        'http://10.0.0.20:8097',
      ]);
      expect(AuthController.serverUrlCandidates('https://argosy.example.com'), [
        'https://argosy.example.com',
      ]);
    });

    test('a public FQDN is HTTPS only — never downgraded to cleartext', () {
      expect(
        AuthController.serverUrlCandidates('argosy.zerogravity.industries'),
        ['https://argosy.zerogravity.industries'],
      );
    });

    test('a private literal tries HTTPS then falls back to HTTP', () {
      expect(AuthController.serverUrlCandidates('10.0.0.45:8096'), [
        'https://10.0.0.45:8096',
        'http://10.0.0.45:8096',
      ]);
    });

    test('a .local and a single-label tailnet name may fall back', () {
      expect(AuthController.serverUrlCandidates('argosy.local'), [
        'https://argosy.local',
        'http://argosy.local',
      ]);
      expect(AuthController.serverUrlCandidates('imperial-construct:5173'), [
        'https://imperial-construct:5173',
        'http://imperial-construct:5173',
      ]);
    });

    test('a trailing slash is trimmed from every candidate', () {
      expect(AuthController.serverUrlCandidates('10.0.0.45:8096/'), [
        'https://10.0.0.45:8096',
        'http://10.0.0.45:8096',
      ]);
      expect(
        AuthController.serverUrlCandidates('https://argosy.example.com/'),
        ['https://argosy.example.com'],
      );
    });

    test('malformed input yields nothing to probe', () {
      expect(AuthController.serverUrlCandidates(''), isEmpty);
      expect(AuthController.serverUrlCandidates('   '), isEmpty);
      // A doubled scheme is text concatenated onto a stale value, not an address.
      expect(
        AuthController.serverUrlCandidates('http://http://10.0.0.20'),
        isEmpty,
      );
    });
  });

  group('isPrivateHost', () {
    test('accepts the ranges that cannot be reached from the internet', () {
      for (final h in [
        'localhost',
        '127.0.0.1',
        '10.0.0.45',
        '192.168.1.10',
        '172.16.0.1',
        '172.31.255.254',
        '169.254.1.1',
        '100.101.102.103', // CGNAT — Tailscale
        'argosy.local',
        'construct.ts.net',
        'imperial-construct',
      ]) {
        expect(AuthController.isPrivateHost(h), isTrue, reason: h);
      }
    });

    test('rejects public names and near-miss literals', () {
      for (final h in [
        'argosy.zerogravity.industries',
        'example.com',
        '8.8.8.8',
        '172.32.0.1', // just outside 172.16/12
        '172.15.0.1',
        '100.63.0.1', // just outside 100.64/10
        '100.128.0.1',
        '11.0.0.1',
      ]) {
        expect(AuthController.isPrivateHost(h), isFalse, reason: h);
      }
    });
  });

  group('setServer', () {
    /// Records what was probed and answers from a fixed reachable set, so the
    /// order and the stop-on-first-hit are both observable.
    ({List<String> tried, ServerProbe probe}) fakeProbe(Set<String> reachable) {
      final tried = <String>[];
      return (
        tried: tried,
        probe: (String url) async {
          tried.add(url);
          return reachable.contains(url)
              ? (ok: true, detail: null)
              : (ok: false, detail: 'Connection refused');
        },
      );
    }

    late _FakeTokenStore store;

    ProviderContainer containerWith(ServerProbe probe) {
      store = _FakeTokenStore();
      final c = ProviderContainer(
        overrides: [
          serverProbeProvider.overrideWithValue(probe),
          tokenStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('commits the HTTPS candidate when the edge answers', () async {
      final f = fakeProbe({'https://argosy.example.com'});
      final c = containerWith(f.probe);

      await c
          .read(authControllerProvider.notifier)
          .setServer('argosy.example.com');

      expect(f.tried, ['https://argosy.example.com']);
      expect(c.read(baseUrlProvider), 'https://argosy.example.com');
      expect(store.savedBaseUrl, 'https://argosy.example.com');
    });

    test('falls back to HTTP on the LAN, in that order', () async {
      final f = fakeProbe({'http://10.0.0.45:8096'});
      final c = containerWith(f.probe);

      await c.read(authControllerProvider.notifier).setServer('10.0.0.45:8096');

      expect(f.tried, ['https://10.0.0.45:8096', 'http://10.0.0.45:8096']);
      expect(c.read(baseUrlProvider), 'http://10.0.0.45:8096');
      expect(store.savedBaseUrl, 'http://10.0.0.45:8096');
    });

    test(
      'never probes cleartext for a public FQDN, even when HTTPS fails',
      () async {
        final f = fakeProbe(<String>{});
        final c = containerWith(f.probe);

        await expectLater(
          c
              .read(authControllerProvider.notifier)
              .setServer('argosy.example.com'),
          throwsA(isA<ApiFailure>()),
        );

        expect(f.tried, ['https://argosy.example.com']);
      },
    );

    test('names every candidate it tried when none answer', () async {
      final f = fakeProbe(<String>{});
      final c = containerWith(f.probe);

      await expectLater(
        c.read(authControllerProvider.notifier).setServer('10.0.0.45:8096'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('https://10.0.0.45:8096'),
              contains('http://10.0.0.45:8096'),
              contains('Connection refused'),
            ),
          ),
        ),
      );
    });

    test('an unusable address is rejected without probing anything', () async {
      final f = fakeProbe(<String>{});
      final c = containerWith(f.probe);

      await expectLater(
        c.read(authControllerProvider.notifier).setServer('http://http://x'),
        throwsA(isA<ApiFailure>()),
      );

      expect(f.tried, isEmpty);
    });
  });
}
