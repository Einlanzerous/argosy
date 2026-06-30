import 'dart:io' show Platform;

import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import '../../widgets/argosy_mark.dart';
import 'auth_controller.dart';

enum _Step { server, signIn, pair }

/// The device pairing flow (ARGY-46): server address → sign in → pick a
/// profile + name the device. Mirrors the web's `LoginView` two-step flow,
/// with an added server-address step (the app isn't served from the server).
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  _Step _step = _Step.server;

  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController();

  List<UserProfile> _profiles = const [];
  String? _selectedProfileId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(baseUrlProvider);
    if (existing.isNotEmpty) _server.text = existing;
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
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
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitServer() => _run(() async {
    await ref.read(authControllerProvider.notifier).setServer(_server.text);
    if (mounted) setState(() => _step = _Step.signIn);
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
      if (_deviceName.text.isEmpty) _deviceName.text = _defaultDeviceName();
      _step = _Step.pair;
    });
  });

  void _submitPair() => _run(() async {
    // On success the gate flips to authenticated and the router redirects
    // away from this screen automatically.
    await ref
        .read(authControllerProvider.notifier)
        .pairDevice(
          username: _username.text.trim(),
          password: _password.text,
          userId: _selectedProfileId!,
          deviceName: _deviceName.text.trim().isEmpty
              ? _defaultDeviceName()
              : _deviceName.text.trim(),
        );
  });

  static String _defaultDeviceName() =>
      Platform.isIOS ? 'iPhone' : 'Android phone';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fill the viewport (minus the vertical padding) so the form stays
            // vertically centred when the keyboard is closed, but can grow and
            // scroll once it opens — keeping the focused field above the
            // keyboard. Without this the lower fields (password) hid behind it.
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  const Align(child: ArgosyMark(size: 76)),
                  const SizedBox(height: 24),
                  _StepRail(step: _step),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildStep(context),
                  ),
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
          },
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return switch (_step) {
      _Step.server => Column(
        key: const ValueKey('server'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OWNED MEDIA · SELF-HOSTED',
            textAlign: TextAlign.center,
            style: text.labelMedium?.copyWith(
              color: ArgosyColors.accent,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Connect to your server',
            textAlign: TextAlign.center,
            style: text.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your household Argosy server address.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _server,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitServer(),
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'http://10.0.0.20:8097',
            ),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'Continue',
            busy: _busy,
            onPressed: _submitServer,
          ),
        ],
      ),
      _Step.signIn => Column(
        key: const ValueKey('signin'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome aboard',
            textAlign: TextAlign.center,
            style: text.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to reach your library.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _username,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitSignIn(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'Sign in',
            busy: _busy,
            onPressed: _submitSignIn,
          ),
          _BackLink(
            label: 'Change server',
            onPressed: _busy
                ? null
                : () => setState(() => _step = _Step.server),
          ),
        ],
      ),
      _Step.pair => Column(
        key: const ValueKey('pair'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Name this device',
            textAlign: TextAlign.center,
            style: text.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            "It'll join your Fleet so you can resume across screens.",
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (_profiles.length > 1) ...[
            _ProfilePicker(
              profiles: _profiles,
              selectedId: _selectedProfileId,
              onChanged: (id) => setState(() => _selectedProfileId = id),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _deviceName,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitPair(),
            decoration: const InputDecoration(labelText: 'Device name'),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'Join the Fleet',
            busy: _busy,
            onPressed: _submitPair,
          ),
          _BackLink(
            label: 'Back',
            onPressed: _busy
                ? null
                : () => setState(() => _step = _Step.signIn),
          ),
        ],
      ),
    };
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final index = _Step.values.indexOf(step);
    const labels = ['Server', 'Sign in', 'Pair'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                color: i <= index
                    ? ArgosyColors.accentLine
                    : ArgosyColors.line2,
              ),
            ),
          _StepDot(n: i + 1, label: labels[i], active: i <= index),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.n, required this.label, required this.active});

  final int n;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? ArgosyColors.accent : Colors.transparent,
            border: Border.all(
              color: active ? Colors.transparent : ArgosyColors.line3,
            ),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? ArgosyColors.ink : ArgosyColors.mute,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: active ? ArgosyColors.cream : ArgosyColors.mute,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({
    required this.profiles,
    required this.selectedId,
    required this.onChanged,
  });

  final List<UserProfile> profiles;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      decoration: const InputDecoration(labelText: 'Profile'),
      dropdownColor: ArgosyColors.panel,
      items: [
        for (final p in profiles)
          DropdownMenuItem(
            value: p.id,
            child: Text('${p.name}  ·  ${p.role.value}'),
          ),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ArgosyColors.ink,
              ),
            )
          : Text(label),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
