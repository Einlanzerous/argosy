import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/button_styles.dart';
import '../../util/format.dart';
import '../auth/auth_controller.dart';
import '../beacon/beacon_providers.dart';
import 'account_providers.dart';

/// The account / Fleet bottom sheet, opened from the Bridge avatar. Shows who's
/// signed in, the shared-playhead Fleet (every paired device), and the account
/// actions (Settings, Sign out). Mirrors the web's account menu.
class AccountSheet extends ConsumerWidget {
  const AccountSheet({super.key});

  /// Opens the sheet over the current screen.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AccountSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final devices = ref.watch(fleetDevicesProvider);
    final selfId = ref.watch(selfDeviceIdProvider).value;
    final fleet = devices.value ?? const <Device>[];
    final self = fleet.where((d) => d.id == selfId).firstOrNull;
    final name = self?.userName?.trim();
    final accountName = (name == null || name.isEmpty) ? 'Your account' : name;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Cap the sheet so a large Fleet scrolls instead of overflowing.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: BoxDecoration(
            color: ArgosyColors.panel,
            borderRadius: BorderRadius.circular(tokens.radiusXl + 6),
            border: Border.all(color: tokens.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: tokens.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Identity header.
              Row(
                children: [
                  _Avatar(
                    initial: accountName.characters.first.toUpperCase(),
                    hasName: name != null && name.isNotEmpty,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accountName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ref.watch(baseUrlProvider),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FleetBanner(count: fleet.length),
              const SizedBox(height: 18),
              Text(
                'FLEET',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ArgosyColors.faint,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: devices.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ArgosyColors.accent,
                        ),
                      ),
                    ),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Couldn't load your Fleet right now.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  data: (list) => ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => _DeviceRow(
                      device: list[i],
                      isSelf: list[i].id == selfId,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: ghostButtonStyle(
                  context,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.settings_outlined, size: 20),
                label: const Text('Settings'),
                onPressed: () {
                  Navigator.of(context).pop();
                  openSettings(context);
                },
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style:
                    ghostButtonStyle(
                      context,
                      minimumSize: const Size.fromHeight(48),
                    ).copyWith(
                      foregroundColor: const WidgetStatePropertyAll(
                        ArgosyColors.danger,
                      ),
                      side: WidgetStatePropertyAll(
                        BorderSide(
                          color: ArgosyColors.danger.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('Log out'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The brass-gradient identity avatar — an initial when we know the profile
/// name, a neutral person glyph otherwise (we don't fabricate one).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial, required this.hasName});

  static const double size = 46;

  final String initial;
  final bool hasName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ArgosyColors.accent, Color(0xFF7A5D2C)],
        ),
      ),
      alignment: Alignment.center,
      child: hasName
          ? Text(
              initial,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
                color: ArgosyColors.ink,
              ),
            )
          : Icon(Icons.person, color: ArgosyColors.ink, size: size * 0.5),
    );
  }
}

class _FleetBanner extends StatelessWidget {
  const _FleetBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    final devices = count == 1 ? '1 device' : '$count devices';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.accentWash,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.accentLine),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_alt, size: 16, color: ArgosyColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your Fleet shares one playhead across $devices.',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: ArgosyColors.accentSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.isSelf});

  final Device device;
  final bool isSelf;

  IconData get _icon => switch (device.platform?.toLowerCase()) {
    'android' => Icons.phone_android,
    'ios' => Icons.phone_iphone,
    'web' => Icons.language,
    'tv' || 'androidtv' || 'tvos' => Icons.tv,
    'macos' || 'windows' || 'linux' => Icons.computer,
    _ => Icons.devices_other,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    final type = (device.platform == null || device.platform!.isEmpty)
        ? 'Device'
        : device.platform![0].toUpperCase() + device.platform!.substring(1);
    final seen = isSelf ? 'this device' : formatRelativeTime(device.lastSeenAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: ArgosyColors.bg2,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: isSelf ? tokens.accentLine : tokens.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.accentWash,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(_icon, size: 18, color: ArgosyColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 7),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: ArgosyColors.green,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$type · $seen',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
