import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/api_providers.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_keyboard.dart';
import '../../../tv/tv_stage.dart';
import '../../../widgets/argosy_mark.dart';
import '../auth_controller.dart';

enum _Step { server, signIn, pair }

/// The TV pairing flow (ARGY-51): server → sign in → pick a profile, driven
/// entirely by the D-pad via the in-app [TvOnScreenKeyboard]. Reuses the same
/// [AuthController] actions as the phone `PairingScreen`; only the input is
/// remote-friendly (the system keyboard can't be operated on a TV).
class TvPairingScreen extends ConsumerStatefulWidget {
  const TvPairingScreen({super.key});

  @override
  ConsumerState<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends ConsumerState<TvPairingScreen> {
  _Step _step = _Step.server;

  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: 'Living Room TV');

  /// The field the on-screen keyboard currently edits.
  TextEditingController? _active;

  List<UserProfile> _profiles = const [];
  String? _selectedProfileId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(baseUrlProvider);
    if (existing.isNotEmpty) _server.text = existing;
    _active = _server;
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  void _type(String ch) {
    final c = _active;
    if (c == null) return;
    setState(() => c.text += ch);
  }

  void _backspace() {
    final c = _active;
    if (c == null || c.text.isEmpty) return;
    setState(() => c.text = c.text.substring(0, c.text.length - 1));
  }

  void _clear() {
    final c = _active;
    if (c == null) return;
    setState(() => c.text = '');
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitServer() => _run(() async {
    await ref.read(authControllerProvider.notifier).setServer(_server.text);
    if (mounted) {
      setState(() {
        _step = _Step.signIn;
        _active = _username;
      });
    }
  });

  void _submitSignIn() => _run(() async {
    final profiles = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text.trim(), _password.text);
    if (profiles.isEmpty) {
      throw const ApiFailure('This account has no profiles yet.');
    }
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selectedProfileId = profiles.first.id;
      _active = _deviceName;
      _step = _Step.pair;
    });
  });

  void _submitPair() => _run(() async {
    // On success the auth gate flips and the router leaves this screen.
    await ref.read(authControllerProvider.notifier).pairDevice(
          username: _username.text.trim(),
          password: _password.text,
          userId: _selectedProfileId!,
          deviceName: _deviceName.text.trim().isEmpty
              ? 'Living Room TV'
              : _deviceName.text.trim(),
        );
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ArgosyMark(size: 64),
                const SizedBox(height: 24),
                _title(context),
                const SizedBox(height: 22),
                ..._stepBody(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ArgosyColors.danger,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (label, sub) = switch (_step) {
      _Step.server => ('Connect to your server', 'Enter your household Argosy server address.'),
      _Step.signIn => ('Welcome aboard', 'Sign in to reach your library.'),
      _Step.pair => ('Who’s aboard?', 'Pick a profile — this TV joins your Fleet.'),
    };
    return Column(
      children: [
        Text(label, textAlign: TextAlign.center, style: t.displayMedium),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: t.bodyLarge?.copyWith(color: ArgosyColors.soft),
        ),
      ],
    );
  }

  List<Widget> _stepBody() {
    return switch (_step) {
      _Step.server => [
          _TvField(
            label: 'Server address',
            value: _server.text,
            active: _active == _server,
            autofocus: true,
            onFocused: () => setState(() => _active = _server),
          ),
          const SizedBox(height: 18),
          _keyboard(),
          const SizedBox(height: 18),
          _action('Continue', _submitServer),
        ],
      _Step.signIn => [
          _TvField(
            label: 'Email',
            value: _username.text,
            active: _active == _username,
            autofocus: true,
            onFocused: () => setState(() => _active = _username),
          ),
          const SizedBox(height: 12),
          _TvField(
            label: 'Password',
            value: _password.text,
            obscure: true,
            active: _active == _password,
            onFocused: () => setState(() => _active = _password),
          ),
          const SizedBox(height: 18),
          _keyboard(),
          const SizedBox(height: 18),
          _action('Sign in', _submitSignIn),
        ],
      _Step.pair => [
          _ProfileRow(
            profiles: _profiles,
            selectedId: _selectedProfileId,
            onSelect: (id) => setState(() => _selectedProfileId = id),
          ),
          const SizedBox(height: 18),
          _TvField(
            label: 'Device name',
            value: _deviceName.text,
            active: _active == _deviceName,
            onFocused: () => setState(() => _active = _deviceName),
          ),
          const SizedBox(height: 18),
          _keyboard(),
          const SizedBox(height: 18),
          _action('Join the Fleet', _submitPair),
        ],
    };
  }

  Widget _keyboard() => TvOnScreenKeyboard(
        onChar: _type,
        onBackspace: _backspace,
        onClear: _clear,
      );

  Widget _action(String label, VoidCallback onPressed) {
    return TvFocusable(
      scale: 1.05,
      onSelect: _busy ? () {} : onPressed,
      child: Container(
        height: 64,
        constraints: const BoxConstraints(minWidth: 360),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ArgosyColors.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ArgosyColors.ink,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ArgosyColors.ink,
                ),
              ),
      ),
    );
  }
}

/// A focusable, read-only field display. Focusing it makes it the keyboard's
/// target ([onFocused]); the system IME is never summoned.
class _TvField extends StatelessWidget {
  const _TvField({
    required this.label,
    required this.value,
    required this.active,
    required this.onFocused,
    this.obscure = false,
    this.autofocus = false,
  });

  final String label;
  final String value;
  final bool active;
  final bool obscure;
  final bool autofocus;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    final shown = obscure ? '•' * value.length : value;
    return TvFocusable(
      scale: 1.02,
      autofocus: autofocus,
      onSelect: onFocused,
      onFocusChange: (f) {
        if (f) onFocused();
      },
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: ArgosyColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? ArgosyColors.accent : ArgosyColors.line2,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ArgosyColors.accent,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Flexible(
                  child: Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 24,
                      color: ArgosyColors.cream,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    width: 2,
                    height: 26,
                    margin: const EdgeInsets.only(left: 2),
                    color: ArgosyColors.accent,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profiles,
    required this.selectedId,
    required this.onSelect,
  });

  final List<UserProfile> profiles;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final p in profiles)
          TvFocusable(
            borderRadius: 16,
            onSelect: () => onSelect(p.id),
            child: Container(
              width: 150,
              height: 150,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.id == selectedId
                    ? ArgosyColors.accentBg2
                    : ArgosyColors.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: p.id == selectedId
                      ? ArgosyColors.accent
                      : ArgosyColors.line2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: ArgosyColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ArgosyColors.cream,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
