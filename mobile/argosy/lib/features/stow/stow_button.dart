import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../theme/button_styles.dart';
import 'stow_controller.dart';
import 'stowed_item.dart';

/// The "Stow" action on a detail screen: packs the item away for offline
/// viewing, shows the packaging/download progress in place, and turns into the
/// remove control once the item is on the device.
///
/// It deliberately reports which of the two phases is running. They fail
/// differently and take wildly different amounts of time — "Packaging 12%" is
/// the server re-encoding and cannot be hurried, "Downloading 12%" is the
/// network — and a single opaque spinner across both is the fastest way to make
/// a twenty-minute encode look like a hang.
class StowButton extends ConsumerWidget {
  const StowButton({super.key, required this.item, this.subtitleLine});

  final MediaItemDetail item;

  /// Secondary line recorded with the stow, for the offline list. Defaults to
  /// the year, or the episode code for an episode.
  final String? subtitleLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the map keeps this rebuilding as progress advances.
    ref.watch(stowControllerProvider);
    ref.watch(stowedItemsProvider);
    final controller = ref.read(stowControllerProvider.notifier);
    final status = controller.statusFor(item.id);

    switch (status.phase) {
      case StowPhase.stowed:
        return FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => _confirmRemove(context, ref),
          icon: const Icon(
            Icons.offline_pin,
            size: 18,
            color: ArgosyColors.accentHi,
          ),
          label: const Text('Stowed'),
        );

      case StowPhase.requesting:
      case StowPhase.packaging:
      case StowPhase.downloading:
        return FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => controller.cancel(item.id),
          icon: _ProgressRing(fraction: status.fraction),
          label: Text(status.label),
        );

      case StowPhase.failed:
        return Tooltip(
          message: status.message ?? 'Stow failed',
          child: FilledButton.icon(
            style: ghostButtonStyle(context),
            onPressed: () => controller.stow(item, subtitleLine: subtitleLine),
            icon: const Icon(
              Icons.error_outline,
              size: 18,
              color: ArgosyColors.danger,
            ),
            label: const Text('Retry stow'),
          ),
        );

      case StowPhase.none:
        return FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => controller.stow(item, subtitleLine: subtitleLine),
          icon: const Icon(Icons.download_for_offline_outlined, size: 18),
          label: const Text('Stow'),
        );
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.bg2,
        title: const Text('Remove download?'),
        content: Text(
          '“${item.title}” will be deleted from this device. '
          'It stays in your library and can be stowed again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(stowControllerProvider.notifier).remove(item.id);
    }
  }
}

/// A small determinate/indeterminate ring sized to sit where a button icon goes.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({this.fraction});

  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        value: fraction,
        strokeWidth: 2,
        color: ArgosyColors.accentHi,
      ),
    );
  }
}
