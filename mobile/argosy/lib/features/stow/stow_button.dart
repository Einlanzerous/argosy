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

/// The season-wide Stow action on a series screen (ARGY-229): one tap queues
/// every playable episode of the season, and from then on the button reads the
/// season's aggregate state — how many are down, whether any are still coming,
/// whether the whole season is on the device — with the matching bulk action
/// behind it.
///
/// Deliberately a count rather than a second progress bar. The episode rows
/// carry the live phase, and a season-level percentage would average a 12%
/// package against a 90% download into a number that means nothing; "3 of 12"
/// is what someone packing for a flight actually wants to know.
class SeasonStowButton extends ConsumerWidget {
  const SeasonStowButton({
    super.key,
    required this.seasonLabel,
    required this.entries,
  });

  /// "Season 2" — named in the confirmation dialogs.
  final String seasonLabel;

  /// The season's playable files in episode order, one entry per file, so a
  /// combined rip is stowed once.
  final List<StowEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(stowControllerProvider);
    ref.watch(stowedItemsProvider);
    final controller = ref.read(stowControllerProvider.notifier);

    final ids = {for (final e in entries) e.itemId}.toList();
    var stowed = 0;
    var busy = 0;
    var failed = 0;
    String? failure;
    for (final id in ids) {
      final status = controller.statusFor(id);
      if (status.phase == StowPhase.stowed) {
        stowed++;
      } else if (status.isBusy) {
        busy++;
      } else if (status.phase == StowPhase.failed) {
        failed++;
        failure ??= status.message;
      }
    }
    final total = ids.length;

    if (busy > 0) {
      return FilledButton.icon(
        style: ghostButtonStyle(context),
        onPressed: () => _confirmCancel(context, ref, ids, remaining: busy),
        // Indeterminate until the first one lands: a determinate ring at zero
        // is a hairline circle that reads as nothing happening.
        icon: _ProgressRing(fraction: stowed == 0 ? null : stowed / total),
        label: Text('Stowing season · $stowed of $total'),
      );
    }
    if (total > 0 && stowed == total) {
      return FilledButton.icon(
        style: ghostButtonStyle(context),
        onPressed: () => _confirmRemove(context, ref, ids),
        icon: const Icon(
          Icons.offline_pin,
          size: 18,
          color: ArgosyColors.accentHi,
        ),
        label: const Text('Season stowed'),
      );
    }
    if (failed > 0) {
      return Tooltip(
        message: failure ?? 'Stow failed',
        child: FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => controller.stowMany(entries),
          icon: const Icon(
            Icons.error_outline,
            size: 18,
            color: ArgosyColors.danger,
          ),
          label: const Text('Retry season'),
        ),
      );
    }
    return FilledButton.icon(
      style: ghostButtonStyle(context),
      onPressed: () => controller.stowMany(entries),
      icon: const Icon(Icons.download_for_offline_outlined, size: 18),
      label: const Text('Stow season'),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    List<String> ids, {
    required int remaining,
  }) async {
    final controller = ref.read(stowControllerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.bg2,
        title: const Text('Cancel season download?'),
        content: Text(
          'Stops the $remaining episode${remaining == 1 ? '' : 's'} of '
          '$seasonLabel still on the way. Anything already on this device '
          'stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel downloads'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    // Queued ones first, the running one last. Cancelling the running job
    // frees the runner to start the next queued one, which would then be
    // cancelled mid-request — and its server-side package with it.
    for (final id in ids) {
      if (controller.statusFor(id).phase == StowPhase.requesting) {
        await controller.cancel(id);
      }
    }
    for (final id in ids) {
      if (controller.statusFor(id).isBusy) await controller.cancel(id);
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    List<String> ids,
  ) async {
    final controller = ref.read(stowControllerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.bg2,
        title: Text('Remove $seasonLabel from this device?'),
        content: Text(
          '${ids.length} episode${ids.length == 1 ? '' : 's'} will be deleted '
          'from this device. They stay in your library and can be stowed '
          'again.',
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
    if (!(ok ?? false)) return;
    for (final id in ids) {
      await controller.remove(id);
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
