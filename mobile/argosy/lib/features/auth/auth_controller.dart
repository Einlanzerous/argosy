import 'dart:async';
import 'dart:io' show Platform;

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../stow/stow_controller.dart';

/// Where the session stands. [unknown] is the pre-bootstrap state used to hold
/// on the splash while we restore + validate a saved device token.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// Owns the auth/session state the router gates on: server selection, the
/// login → profile → device-registration pairing flow, token persistence, and
/// startup restore. Mirrors the web's session store + `LoginView` flow.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _bootstrap();
    return AuthStatus.unknown;
  }

  /// This device's platform tag for the Fleet (`android` / `ios`).
  String get platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _bootstrap() async {
    final store = ref.read(tokenStoreProvider);
    try {
      await store.load();
    } catch (_) {
      // Secure storage unavailable/corrupt (or absent in tests) — treat as
      // signed-out rather than bricking the app.
      state = AuthStatus.unauthenticated;
      return;
    }

    final base = store.baseUrl;
    if (base != null && base.isNotEmpty) {
      ref.read(baseUrlProvider.notifier).set(base);
    }

    if (!store.hasToken) {
      state = AuthStatus.unauthenticated;
      return;
    }

    // Validate the restored token. A definitive 401 means it was revoked →
    // re-pair; a transport error (server unreachable) keeps us optimistically
    // signed in so an offline launch isn't locked out.
    try {
      await ref.read(authApiProvider).getCurrentSession();
      state = AuthStatus.authenticated;
      // The server answered, so this is the first chance to hand over anything
      // watched while it couldn't be reached (ARGY-49) — a flight's worth of
      // resume positions lands here rather than waiting for the next play.
      unawaited(flushOfflineProgress(ref));
    } on ApiException catch (e) {
      if (e.code == 401) {
        await store.clearToken();
        state = AuthStatus.unauthenticated;
      } else {
        state = AuthStatus.authenticated;
      }
    } catch (_) {
      state = AuthStatus.authenticated;
    }
  }

  /// Persist + activate the household server address, then verify it's
  /// reachable. Throws [ApiFailure] if the address is unusable.
  Future<void> setServer(String rawUrl) async {
    final candidates = serverUrlCandidates(rawUrl);
    if (candidates.isEmpty) {
      throw const ApiFailure(
        'Enter a valid server address, e.g. argosy.example.com or '
        '10.0.0.20:8097',
      );
    }
    // Probe before committing: the address is only stored once something at the
    // other end answers, so a failed guess doesn't leave the app pointed at a
    // host that isn't there.
    final probe = ref.read(serverProbeProvider);
    String? detail;
    for (final url in candidates) {
      final result = await probe(url);
      if (result.ok) {
        await ref.read(tokenStoreProvider).setBaseUrl(url);
        ref.read(baseUrlProvider.notifier).set(url);
        return;
      }
      detail = result.detail;
    }
    // Name the addresses we actually tried — with a scheme guessed on the
    // user's behalf, "couldn't connect" alone doesn't say what was attempted.
    throw ApiFailure(
      "Couldn't reach ${candidates.join(' or ')} — "
      '${detail ?? 'check the address is correct and the server is reachable.'}',
    );
  }

  /// Step 1 — authenticate the household account; returns its profiles to pick.
  Future<List<UserProfile>> login(String email, String password) async {
    try {
      final res = await ref
          .read(authApiProvider)
          .login(LoginRequest(email: email, password: password));
      return res?.profiles ?? const [];
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Step 2 — register this device against the chosen profile and persist the
  /// returned device token. Flips the gate to authenticated on success.
  /// A freshly provisioned account has no profiles yet (ARGY-159): pass
  /// [newProfileName] instead of [userId] and the server creates the first
  /// profile in the same call.
  Future<void> pairDevice({
    required String email,
    required String password,
    String? userId,
    String? newProfileName,
    required String deviceName,
  }) async {
    try {
      final installId = await ref.read(tokenStoreProvider).ensureInstallId();
      final res = await ref
          .read(authApiProvider)
          .registerDevice(
            DeviceRegistrationRequest(
              email: email,
              password: password,
              userId: userId,
              newProfileName: newProfileName,
              deviceName: deviceName,
              platform: platform,
              installId: installId,
            ),
          );
      final token = res?.token;
      if (token == null || token.isEmpty) {
        throw const ApiFailure('Pairing succeeded but returned no token.');
      }
      await ref.read(tokenStoreProvider).setToken(token);
      state = AuthStatus.authenticated;
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Adopt a device token obtained out-of-band — e.g. TV code-pairing, where the
  /// token is minted server-side once a web user approves the code (ARGY-112).
  /// The token is already valid, so we just persist it and open the gate.
  Future<void> adoptToken(String token) async {
    await ref.read(tokenStoreProvider).setToken(token);
    state = AuthStatus.authenticated;
  }

  /// In-place profile switch (ARGY-85): re-point THIS device to [userId] without
  /// re-pairing. The device token is unchanged — only its profile binding moves.
  /// [password] is the account password, required by the server only when the
  /// target is an admin profile (so a viewer can't silently assume admin); pass
  /// null for viewer targets. Callers refresh profile-keyed providers (home,
  /// prefs, fleet, session) on success. Returns the refreshed session.
  Future<Session?> switchProfile({
    required String userId,
    String? password,
  }) async {
    try {
      return await ref
          .read(authApiProvider)
          .switchDeviceProfile(
            DeviceSwitchRequest(userId: userId, password: password),
          );
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Sign out / re-pair. Keeps the server address (only the token is cleared).
  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clearToken();
    state = AuthStatus.unauthenticated;
  }

  /// Ordered base-URL candidates for a typed server address, likeliest first.
  /// Empty when the input can't be a server address at all.
  ///
  /// An explicit scheme is always honoured as typed — one candidate, no
  /// guessing. A bare hostname used to become `http://…` unconditionally, which
  /// aims at plain HTTP on port 80 and fails outright against an HTTPS-only
  /// edge: `argosy.zerogravity.industries` answers only on 443, so port 80
  /// returns a connection failure rather than a redirect, and the user got an
  /// eight-second spinner and a generic network error (ARGY-192).
  ///
  /// So a bare host is tried as HTTPS first and falls back to cleartext **only
  /// when the host is private** ([isPrivateHost]). A public FQDN is never
  /// silently downgraded to HTTP; the LAN and the tailnet are the only cases
  /// that legitimately need it.
  static List<String> serverUrlCandidates(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const [];
    // Reject malformed input like a doubled scheme (e.g. text concatenated onto
    // a stale value) rather than silently aiming at the wrong host.
    if ('://'.allMatches(s).length > 1) return const [];
    final hasScheme = s.contains('://');
    final parsed = Uri.tryParse(hasScheme ? s : 'https://$s');
    if (parsed == null || parsed.host.isEmpty) return const [];
    String trim(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;
    if (hasScheme) return [trim(s)];
    return [
      trim('https://$s'),
      if (isPrivateHost(parsed.host)) trim('http://$s'),
    ];
  }

  /// Whether cleartext is acceptable for [host] — true only for addresses that
  /// cannot be reached from the public internet, so guessing `http://` for one
  /// can't put a household's credentials on the open wire.
  ///
  /// Beyond the RFC1918/loopback/link-local literals: a single-label name
  /// (`imperial-construct`) has no TLD and so cannot be a public FQDN, and
  /// Tailscale's MagicDNS names and CGNAT range carry their own WireGuard
  /// encryption — plain HTTP inside the tailnet isn't the downgrade this rule
  /// exists to prevent, and it is how this household actually connects.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost') return true;
    // IPv6 first: `Uri.host` strips the brackets, so these arrive as a bare
    // address with colons and no dot. Deciding them here keeps the single-label
    // rule below from reading a *public* v6 literal as a TLD-less name and
    // handing it a cleartext fallback — loopback, link-local (fe80::/10) and
    // unique-local (fc00::/7, i.e. an fc/fd prefix) are the only private ones.
    if (h.contains(':')) {
      return h == '::1' ||
          h.startsWith('fe80:') ||
          h.startsWith('fc') ||
          h.startsWith('fd');
    }
    if (!h.contains('.')) return true;
    if (h.endsWith('.local') ||
        h.endsWith('.internal') ||
        h.endsWith('.ts.net')) {
      return true;
    }
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    if (a == 10 || a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT / Tailscale
    return false;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
);
