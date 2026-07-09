import 'dart:async';

import 'package:argosy_api/api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../platform/server_discovery.dart';
import 'auth_controller.dart';

/// Where the PIN-first onboarding stands (ARGY-123).
enum PinPhase {
  /// Looking for a server: the saved address first, then LAN discovery.
  searching,

  /// No reachable server — offer "search again" and manual address entry.
  notFound,

  /// A code is on screen and we're polling for approval.
  waiting,
}

/// Drives PIN-first onboarding for both the phone [PairingScreen] and the TV
/// [TvPairingScreen]: find a server (saved address → mDNS discovery), mint a
/// pairing code announcing this device's name/platform, poll for approval, and
/// adopt the token — so a new device joins the Fleet without anyone typing a
/// server address or credentials on it. The owning screen renders [phase] and
/// keeps its own manual/typed fallback steps.
class PinPairingController extends ChangeNotifier {
  PinPairingController(
    this._ref, {
    required this.deviceName,
    required this.platform,
  });

  final WidgetRef _ref;

  /// Announced to the server so the approver sees what they're blessing.
  final String deviceName;
  final String platform;

  PinPhase phase = PinPhase.searching;
  String? code;

  /// Friendly server name from mDNS, when the server was discovered.
  String? serverName;

  /// The base URL the code was minted against (shown in the instructions).
  String? baseUrl;
  String? error;

  Timer? _pollTimer;

  /// Bumped on every restart/dispose so a superseded async chain (an old
  /// discovery resolving late, a stale poll) can tell it lost the race and
  /// must not touch state.
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Entry point: ping the saved server if there is one, otherwise browse the
  /// LAN; on success mint a code and start polling.
  Future<void> connect() async {
    final gen = _restart();

    final saved = _ref.read(baseUrlProvider);
    if (saved.isNotEmpty) {
      try {
        await _ref.read(systemApiProvider).ping();
        if (gen != _generation) return;
        return _startLink(gen);
      } catch (_) {
        if (gen != _generation) return;
        // Saved server unreachable (network moved?) — try discovery.
      }
    }

    final found = await discoverServer();
    if (gen != _generation) return;
    if (found == null) {
      phase = PinPhase.notFound;
      notifyListeners();
      return;
    }
    try {
      await _ref.read(authControllerProvider.notifier).setServer(found.url);
    } catch (_) {
      if (gen != _generation) return;
      phase = PinPhase.notFound;
      error = 'Found ${found.name} at ${found.url}, but could not reach it.';
      notifyListeners();
      return;
    }
    if (gen != _generation) return;
    serverName = found.name;
    await _startLink(gen);
  }

  /// The screen already set + verified the server (manual address entry) —
  /// skip discovery and mint a code against it.
  Future<void> startOnCurrentServer() => _startLink(_restart());

  int _restart() {
    final gen = ++_generation;
    _pollTimer?.cancel();
    phase = PinPhase.searching;
    code = null;
    error = null;
    serverName = null;
    notifyListeners();
    return gen;
  }

  Future<void> _startLink(int gen) async {
    _pollTimer?.cancel();
    baseUrl = _ref.read(baseUrlProvider);
    try {
      final res = await _ref.read(authApiProvider).startLink(
            linkStartRequest: LinkStartRequest(
              deviceName: deviceName,
              platform: platform,
            ),
          );
      if (gen != _generation) return;
      final minted = res?.code;
      if (minted == null) {
        phase = PinPhase.notFound;
        error = "Couldn't start pairing. Check the server and try again.";
        notifyListeners();
        return;
      }
      code = minted;
      phase = PinPhase.waiting;
      notifyListeners();
      _pollTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _poll(gen));
    } catch (_) {
      if (gen != _generation) return;
      phase = PinPhase.notFound;
      error = "Couldn't start pairing. Check the server and try again.";
      notifyListeners();
    }
  }

  Future<void> _poll(int gen) async {
    final c = code;
    if (c == null || gen != _generation) return;
    try {
      final res = await _ref.read(authApiProvider).getLinkStatus(c);
      if (gen != _generation) return;
      if (res?.status == LinkStatusResponseStatusEnum.approved &&
          res?.token != null) {
        _pollTimer?.cancel();
        // Auth gate flips → the router leaves the pairing screen.
        await _ref
            .read(authControllerProvider.notifier)
            .adoptToken(res!.token!);
      }
    } on ApiException catch (e) {
      if (gen != _generation) return;
      // The code expired or was consumed — mint a fresh one.
      if (e.code == 404) await _startLink(gen);
    } catch (_) {
      // Transient network blip — keep polling.
    }
  }
}
