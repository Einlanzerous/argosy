import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../util/format.dart';
import 'stow_controller.dart';
import 'stowed_item.dart';

/// The Hold: everything packed away on this device.
///
/// This screen is the one part of the app that has to work with nothing behind
/// it — no server, no session refresh, no catalog. It reads the on-device index
/// and nothing else, which is why the rows carry their own titles and runtimes
/// rather than looking anything up.
class StowedScreen extends ConsumerWidget {
  const StowedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(stowedItemsProvider);
    // Rebuild while a download is in flight so a stow started elsewhere appears
    // here as it lands.
    ref.watch(stowControllerProvider);

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      appBar: AppBar(
        backgroundColor: ArgosyColors.bg,
        title: const Text('The Hold'),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't read what's stowed on this device.\n$e",
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArgosyColors.dim),
            ),
          ),
        ),
        data: (list) =>
            list.isEmpty ? const _EmptyHold() : _StowedList(items: list),
      ),
    );
  }
}

class _EmptyHold extends StatelessWidget {
  const _EmptyHold();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.download_for_offline_outlined,
              size: 48,
              color: ArgosyColors.faint,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing stowed yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Stow a film or episode from its detail screen and it will play '
              'here with no connection — on a flight, or anywhere else the '
              'server is out of reach.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ArgosyColors.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _StowedList extends ConsumerWidget {
  const _StowedList({required this.items});

  final List<StowedItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = items.fold<int>(0, (sum, e) => sum + e.bytes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              const Icon(
                Icons.sd_storage_outlined,
                size: 16,
                color: ArgosyColors.dim,
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length} ${items.length == 1 ? 'item' : 'items'} · '
                '${formatBytes(total)} on this device',
                style: const TextStyle(color: ArgosyColors.dim),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _StowedRow(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _StowedRow extends ConsumerWidget {
  const _StowedRow({required this.item});

  final StowedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    // Downloads run in a service now (ARGY-201), so an unfinished row is as
    // likely to be one still coming down — started, pocketed, and looked in on —
    // as one that stopped. Telling someone to "stow it again to resume"
    // something that is actively downloading would be nonsense, so ask.
    final live = ref
        .read(stowControllerProvider.notifier)
        .statusFor(item.itemId);
    final active = item.incomplete && live.isBusy;
    // An unfinished row exists to account for bytes, so it says what they are
    // and what will happen to them rather than posing as something watchable.
    final subtitle = active
        ? '${live.label}   •   '
              '${formatBytes(live.receivedBytes > 0 ? live.receivedBytes : item.bytes)}'
              ' so far'
        : item.incomplete
        ? 'Unfinished — ${formatBytes(item.bytes)} downloaded'
              '   •   Stow it again to resume'
        : [
            if (item.subtitleLine != null && item.subtitleLine!.isNotEmpty)
              item.subtitleLine!,
            formatBytes(item.bytes),
            if (item.durationSeconds > 0) formatRuntime(item.durationSeconds),
          ].join('   •   ');

    return Material(
      color: ArgosyColors.bg2,
      borderRadius: BorderRadius.circular(tokens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius),
        // Offline playback goes through the normal player route: it resolves the
        // local file itself, so a stowed item plays the same way online or off.
        // An unfinished download has no file behind it, so it isn't tappable.
        onTap: item.incomplete ? null : () => openPlayer(context, item.itemId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                item.incomplete
                    ? Icons.downloading_outlined
                    : Icons.offline_pin,
                color: item.incomplete
                    ? ArgosyColors.dim
                    : ArgosyColors.accentHi,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ArgosyColors.dim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from this device',
                icon: const Icon(Icons.delete_outline, color: ArgosyColors.dim),
                onPressed: () => _confirmRemove(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArgosyColors.bg2,
        title: const Text('Remove download?'),
        content: Text(
          item.incomplete
              ? 'The unfinished download of “${item.title}” will be '
                    'deleted, freeing ${formatBytes(item.bytes)}. It stays in '
                    'your library and can be stowed again from the start.'
              : '“${item.title}” will be deleted from this device, '
                    'freeing ${formatBytes(item.bytes)}. It stays in your '
                    'library.',
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
      await ref.read(stowControllerProvider.notifier).remove(item.itemId);
    }
  }
}
