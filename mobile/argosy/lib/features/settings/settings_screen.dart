import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/button_styles.dart';
import '../../widgets/async_view.dart';
import '../account/account_providers.dart';
import '../auth/auth_controller.dart';
import '../home/home_providers.dart';
import 'link_device_sheet.dart';
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
              title: const Text('Auto-play next episode',
                  style: TextStyle(color: ArgosyColors.cream)),
              subtitle: const Text(
                  'When a series episode ends, roll into the next one with an Up Next countdown.',
                  style: TextStyle(color: ArgosyColors.dim, fontSize: 12)),
              value: data.device.seriesAutoAdvance ?? true,
              onChanged: (v) => _guard(context, () => ctrl.setSeriesAutoAdvance(v)),
            ),
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
            const SizedBox(height: 16),
            _label('Caption position'),
            _choices<DevicePreferencesCaptionPositionEnum>(
              context,
              options: const [
                ('Bottom', DevicePreferencesCaptionPositionEnum.bottom),
                ('Raised', DevicePreferencesCaptionPositionEnum.raised),
                ('Higher', DevicePreferencesCaptionPositionEnum.higher),
              ],
              selected: data.device.captionPosition ??
                  DevicePreferencesCaptionPositionEnum.raised,
              onSelect: (v) => _guard(context, () => ctrl.setCaptionPosition(v)),
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

            _section('Fleet'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_to_queue_outlined,
                  color: ArgosyColors.dim),
              title: const Text('Link a device',
                  style: TextStyle(color: ArgosyColors.cream)),
              subtitle: const Text(
                  'Approve the PIN shown on a new TV or phone — no typing there.',
                  style: TextStyle(color: ArgosyColors.dim, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: ArgosyColors.dim),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: ArgosyColors.panel,
                isScrollControlled: true,
                builder: (_) => const LinkDeviceSheet(),
              ),
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
              label: const Text('Switch profile'),
              onPressed: () => _switchProfile(context, ref),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: ghostButtonStyle(context, minimumSize: const Size.fromHeight(48))
                  .copyWith(foregroundColor: WidgetStatePropertyAll(_danger)),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Sign out / change server'),
              onPressed: () => _confirmReauth(
                context,
                ref,
                title: 'Sign out?',
                body: 'Signs this device out so you can sign in to a different '
                    'account or server address, then re-pair. You can stay offline, '
                    'but you will need to re-pair to watch again.',
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

  /// In-place profile switch (ARGY-85): pick another profile in this account and
  /// re-bind the device without re-pairing. Opens the picker sheet.
  Future<void> _switchProfile(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ArgosyColors.panel,
      builder: (_) => const _ProfilePickerSheet(),
    );
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

/// In-place profile switcher (ARGY-85): lists the account's profiles and re-binds
/// this device to the chosen one without re-pairing. The current profile is
/// marked and not tappable; admin targets are gated behind the account password.
class _ProfilePickerSheet extends ConsumerWidget {
  const _ProfilePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(accountProfilesProvider);
    final currentId = ref.watch(currentSessionProvider).value?.userId;
    return SafeArea(
      child: profiles.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator(color: ArgosyColors.accentHi)),
        ),
        error: (_, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text("Couldn't load profiles. Try again.",
              style: TextStyle(color: ArgosyColors.dim)),
        ),
        data: (list) => ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Switch profile',
                  style: TextStyle(
                      color: ArgosyColors.cream,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            for (final p in list)
              _profileTile(context, ref, p, isCurrent: p.id == currentId),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(
    BuildContext context,
    WidgetRef ref,
    ProfileSummary p, {
    required bool isCurrent,
  }) {
    final isAdmin = p.role == Role.admin;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.argosy.accentWash,
        child: Text(
          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
          style: const TextStyle(color: ArgosyColors.accentHi, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(p.name,
          style: TextStyle(
            color: isCurrent ? ArgosyColors.accentHi : ArgosyColors.cream,
            fontWeight: FontWeight.w600,
          )),
      subtitle: Text(isAdmin ? 'Admin' : 'Viewer',
          style: const TextStyle(color: ArgosyColors.dim, fontSize: 12)),
      trailing: isCurrent
          ? const Icon(Icons.check, color: ArgosyColors.accentHi, size: 20)
          : (isAdmin
              ? const Icon(Icons.lock_outline, color: ArgosyColors.dim, size: 18)
              : null),
      onTap: isCurrent ? null : () => _pick(context, ref, p),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, ProfileSummary p) async {
    // Capture before any await so we don't touch a possibly-popped sheet context.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String? password;
    if (p.role == Role.admin) {
      password = await _promptPassword(context, p.name);
      if (password == null || password.isEmpty) return; // cancelled / empty
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .switchProfile(userId: p.id, password: password);
    } on ApiFailure catch (f) {
      // Keep the sheet open so they can retry (e.g. wrong password → 403).
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
      return;
    }

    // Refresh everything keyed to the active profile: session/role, the fleet
    // (whose device name now points to the new profile), prefs, and home layout.
    ref.invalidate(currentSessionProvider);
    ref.invalidate(accountProfilesProvider);
    ref.invalidate(fleetDevicesProvider);
    ref.invalidate(settingsControllerProvider);
    ref.invalidate(homeDataProvider);

    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Switched to ${p.name}')));
  }

  Future<String?> _promptPassword(BuildContext context, String profileName) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.panel,
        title: const Text('Account password', style: TextStyle(color: ArgosyColors.cream)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switching to “$profileName” (an admin profile) needs the account password.',
                style: const TextStyle(color: ArgosyColors.dim, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: ArgosyColors.cream),
              decoration: const InputDecoration(hintText: 'Password'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: ArgosyColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Switch', style: TextStyle(color: ArgosyColors.accentHi)),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
