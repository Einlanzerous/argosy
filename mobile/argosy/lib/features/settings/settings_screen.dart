import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/button_styles.dart';
import '../../widgets/async_view.dart';
import '../auth/auth_controller.dart';
import 'settings_controller.dart';

/// Curated subtitle languages for the default-track preference. `null` = let the
/// server/player pick (the item's default/forced track). Codes are ISO-639-1 to
/// match what the catalog stores.
const _subtitleLanguages = <(String, String?)>[
  ('Automatic', null),
  ('English', 'en'),
  ('Spanish', 'es'),
  ('French', 'fr'),
  ('German', 'de'),
  ('Italian', 'it'),
  ('Portuguese', 'pt'),
  ('Japanese', 'ja'),
  ('Korean', 'ko'),
  ('Chinese', 'zh'),
  ('Russian', 'ru'),
];

/// Caption colour swatches (hex stored as `#RRGGBB`, read back by the player's
/// caption config).
const _captionColors = <(String, String)>[
  ('White', '#FFFFFF'),
  ('Cream', '#EAEAE5'),
  ('Yellow', '#F1C40F'),
  ('Cyan', '#22D3EE'),
  ('Green', '#A3E635'),
];

const _captionSizes = <(String, double)>[
  ('Small', 0.85),
  ('Default', 1.0),
  ('Large', 1.25),
  ('X-Large', 1.5),
];

/// Device + account settings, mirroring the web `SettingsView` and reusing the
/// preference APIs: playback (per-device), home layout (per-user), and the
/// account/server actions (profile switch, sign out, re-pair).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView(
        value: settings,
        onRetry: () => ref.invalidate(settingsControllerProvider),
        builder: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _section('Playback'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: ArgosyColors.accentHi,
              title: const Text('Subtitles on by default',
                  style: TextStyle(color: ArgosyColors.cream)),
              subtitle: const Text('Show a subtitle track automatically when one matches.',
                  style: TextStyle(color: ArgosyColors.dim, fontSize: 12)),
              value: data.device.subtitleEnabled,
              onChanged: (v) => _guard(context, () => ctrl.setSubtitlesEnabled(v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Subtitle language',
                  style: TextStyle(color: ArgosyColors.cream)),
              subtitle: Text(_languageLabel(data.device.subtitleLanguage),
                  style: const TextStyle(color: ArgosyColors.dim, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: ArgosyColors.dim),
              onTap: () => _pickLanguage(context, ref, data.device.subtitleLanguage),
            ),
            const SizedBox(height: 12),
            _label('Caption size'),
            _choices<double>(
              context,
              options: _captionSizes,
              selected: (data.device.captionScale ?? 1.0).toDouble(),
              onSelect: (v) => _guard(context, () => ctrl.setCaptionScale(v)),
            ),
            const SizedBox(height: 16),
            _label('Caption colour'),
            _colorSwatches(
              context,
              selected: data.device.captionColor ?? '#FFFFFF',
              onSelect: (hex) => _guard(context, () => ctrl.setCaptionColor(hex)),
            ),
            const SizedBox(height: 16),
            _label('Caption background'),
            _choices<DevicePreferencesCaptionBackgroundEnum>(
              context,
              options: const [
                ('Translucent', DevicePreferencesCaptionBackgroundEnum.translucent),
                ('Solid', DevicePreferencesCaptionBackgroundEnum.solid),
                ('None', DevicePreferencesCaptionBackgroundEnum.none),
              ],
              selected: data.device.captionBackground ??
                  DevicePreferencesCaptionBackgroundEnum.translucent,
              onSelect: (v) => _guard(context, () => ctrl.setCaptionBackground(v)),
            ),
            const SizedBox(height: 28),

            _section('Home'),
            _layoutOption(
              context,
              title: 'Focused',
              description: 'Just your rows — Continue Watching, On Deck, Newly Arrived.',
              value: UserPreferencesHomeLayoutEnum.focused,
              selected: data.user.homeLayout,
              onSelect: (v) => _guard(context, () => ctrl.setHomeLayout(v)),
            ),
            _layoutOption(
              context,
              title: 'Discovery',
              description: 'Everything, plus Vaults and genre rows to browse.',
              value: UserPreferencesHomeLayoutEnum.discovery,
              selected: data.user.homeLayout,
              onSelect: (v) => _guard(context, () => ctrl.setHomeLayout(v)),
            ),
            const SizedBox(height: 28),

            _section('Account'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_outlined, color: ArgosyColors.dim),
              title: const Text('Server', style: TextStyle(color: ArgosyColors.cream)),
              subtitle: Text(ref.watch(baseUrlProvider),
                  style: const TextStyle(color: ArgosyColors.dim, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: ghostButtonStyle(context, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.switch_account_outlined, size: 20),
              label: const Text('Switch profile / re-pair'),
              onPressed: () => _confirmReauth(
                context,
                ref,
                title: 'Switch profile or server?',
                body: 'This signs the device out so you can pick a different '
                    'profile or server address, then re-pair.',
                confirmLabel: 'Continue',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: ghostButtonStyle(context, minimumSize: const Size.fromHeight(48))
                  .copyWith(foregroundColor: WidgetStatePropertyAll(_danger)),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Sign out'),
              onPressed: () => _confirmReauth(
                context,
                ref,
                title: 'Sign out?',
                body: 'You can stay offline, but you will need to sign in and '
                    're-pair this device to watch again.',
                confirmLabel: 'Sign out',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- account actions -----------------------------------------------------

  Future<void> _confirmReauth(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.panel,
        title: Text(title, style: const TextStyle(color: ArgosyColors.cream)),
        content: Text(body, style: const TextStyle(color: ArgosyColors.dim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: ArgosyColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: const TextStyle(color: ArgosyColors.accentHi)),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      // Sign-out flips the auth gate; the router redirects to the pairing flow
      // (server address pre-filled), where a different profile/server is chosen.
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, String? current) async {
    final ctrl = ref.read(settingsControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ArgosyColors.panel,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (label, code) in _subtitleLanguages)
              ListTile(
                title: Text(label, style: TextStyle(
                  color: code == current ? ArgosyColors.accentHi : ArgosyColors.cream,
                  fontWeight: code == current ? FontWeight.w600 : FontWeight.w400,
                )),
                trailing: code == current
                    ? const Icon(Icons.check, color: ArgosyColors.accentHi, size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _guard(context, () => ctrl.setSubtitleLanguage(code));
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- reusable bits -------------------------------------------------------

  /// Runs a save and surfaces any failure as a SnackBar (the controller already
  /// reverted the optimistic state).
  Future<void> _guard(BuildContext context, Future<void> Function() save) async {
    try {
      await save();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that setting. Try again.")),
        );
      }
    }
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: ArgosyColors.accentHi,
                fontSize: 12,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: ArgosyColors.faint, fontSize: 13)),
      );

  Widget _choices<T>(
    BuildContext context, {
    required List<(String, T)> options,
    required T selected,
    required ValueChanged<T> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, value) in options)
          _Pill(
            label: label,
            selected: value == selected,
            onTap: () => onSelect(value),
          ),
      ],
    );
  }

  Widget _colorSwatches(
    BuildContext context, {
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 12,
      children: [
        for (final (name, hex) in _captionColors)
          GestureDetector(
            onTap: () => onSelect(hex),
            child: Tooltip(
              message: name,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hex(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hex.toUpperCase() == selected.toUpperCase()
                        ? ArgosyColors.accentHi
                        : context.argosy.line2,
                    width: hex.toUpperCase() == selected.toUpperCase() ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _layoutOption(
    BuildContext context, {
    required String title,
    required String description,
    required UserPreferencesHomeLayoutEnum value,
    required UserPreferencesHomeLayoutEnum selected,
    required ValueChanged<UserPreferencesHomeLayoutEnum> onSelect,
  }) {
    final isSelected = value == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? context.argosy.accentWash : ArgosyColors.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isSelected ? context.argosy.accentLine : context.argosy.line2),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? ArgosyColors.accentHi : ArgosyColors.dim,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: ArgosyColors.cream, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: const TextStyle(color: ArgosyColors.dim, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _danger = Color(0xFFE07A5F);

String _languageLabel(String? code) {
  for (final (label, c) in _subtitleLanguages) {
    if (c == code) return label;
  }
  return code ?? 'Automatic';
}

Color _hex(String hex) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFFFFFFF);
}

/// A small selectable pill matching the app's chip aesthetic (brass wash when
/// selected, hairline otherwise).
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? context.argosy.accentWash : ArgosyColors.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? context.argosy.accentLine : context.argosy.line2),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? ArgosyColors.accentHi : ArgosyColors.cream,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            )),
      ),
    );
  }
}
