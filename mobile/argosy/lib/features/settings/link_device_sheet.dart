import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';

/// Approve a new device's pairing PIN from this (already signed-in) phone —
/// the other half of PIN-first onboarding (ARGY-123). Two stages: look the
/// code up (shows what device announced itself, prefills its name), then
/// approve. Mirrors the web `/link` page.
class LinkDeviceSheet extends ConsumerStatefulWidget {
  const LinkDeviceSheet({super.key});

  @override
  ConsumerState<LinkDeviceSheet> createState() => _LinkDeviceSheetState();
}

class _LinkDeviceSheetState extends ConsumerState<LinkDeviceSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();

  /// Set once the code was looked up and is pending approval.
  bool _confirmed = false;
  String? _platform;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code from the new device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_confirmed) {
        final st = await ref.read(authApiProvider).getLinkStatus(code);
        if (!mounted) return;
        if (st?.status == LinkStatusResponseStatusEnum.approved) {
          setState(() => _error = 'That code was already used. Start over on the new device.');
          return;
        }
        setState(() {
          _confirmed = true;
          _platform = st?.platform;
          if (_name.text.isEmpty) _name.text = st?.deviceName ?? '';
        });
        return;
      }
      await ref.read(authApiProvider).approveLink(
            code,
            linkApproveRequest: _name.text.trim().isEmpty
                ? null
                : LinkApproveRequest(deviceName: _name.text.trim()),
          );
      if (!mounted) return;
      setState(() => _done = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _confirmed = false;
        _error = switch (e.code) {
          404 => 'Code not found — it may have expired. Start over on the new device.',
          409 => 'That code was already used. Start over on the new device.',
          _ => 'Something went wrong. Please try again.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _done ? _success(context) : _form(context),
        ),
      ),
    );
  }

  List<Widget> _success(BuildContext context) => [
        const Icon(Icons.check_circle_outline,
            color: ArgosyColors.accentHi, size: 44),
        const SizedBox(height: 12),
        const Text(
          'Linked. The new device signs itself in within a few seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ArgosyColors.cream, fontSize: 15),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ];

  List<Widget> _form(BuildContext context) => [
        const Text('Link a device',
            style: TextStyle(
                color: ArgosyColors.cream,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Enter the code shown on the new TV or phone.',
          style: TextStyle(color: ArgosyColors.dim, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          enabled: !_confirmed,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(6)],
          style: const TextStyle(
            color: ArgosyColors.cream,
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: 'ABC123'),
          onSubmitted: (_) => _submit(),
        ),
        if (_confirmed) ...[
          const SizedBox(height: 12),
          Text(
            _platform == null
                ? 'Name this device for your Fleet:'
                : 'This adds a ${_platformLabel(_platform!)} to your Fleet as:',
            style: const TextStyle(color: ArgosyColors.dim, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.go,
            style: const TextStyle(color: ArgosyColors.cream),
            decoration: const InputDecoration(labelText: 'Device name'),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArgosyColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: ArgosyColors.ink),
                )
              : Text(_confirmed ? 'Approve' : 'Look up code'),
        ),
      ];
}

String _platformLabel(String platform) => switch (platform) {
      'androidtv' => 'TV',
      'android' => 'phone',
      'ios' => 'iPhone or iPad',
      'web' => 'browser',
      _ => 'device',
    };
