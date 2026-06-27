import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import 'detail_widgets.dart';

/// "Add to Vault" action — opens a sheet of the vaults the profile may curate
/// (its own, or any shared household vault) and files the title into the chosen
/// one, with an inline "new vault" path. Exactly one of [movieId] / [seriesId].
class AddToVaultButton extends ConsumerWidget {
  const AddToVaultButton({super.key, this.movieId, this.seriesId})
      : assert(movieId != null || seriesId != null,
            'AddToVaultButton needs a movieId or seriesId');

  final String? movieId;
  final String? seriesId;

  /// Opens the add-to-vault sheet directly, without rendering the phone button —
  /// the TV detail screens drive it from their own focusable `+` affordance.
  static Future<void> showFor(BuildContext context,
          {String? movieId, String? seriesId}) =>
      _AddToVaultSheet.show(context, movieId: movieId, seriesId: seriesId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      style: ghostButtonStyle(context),
      onPressed: () =>
          _AddToVaultSheet.show(context, movieId: movieId, seriesId: seriesId),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add to Vault'),
    );
  }
}

class _AddToVaultSheet extends ConsumerStatefulWidget {
  const _AddToVaultSheet({this.movieId, this.seriesId});

  final String? movieId;
  final String? seriesId;

  static Future<void> show(BuildContext context,
      {String? movieId, String? seriesId}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: ArgosyColors.panel,
      showDragHandle: true,
      builder: (_) => _AddToVaultSheet(movieId: movieId, seriesId: seriesId),
    );
  }

  @override
  ConsumerState<_AddToVaultSheet> createState() => _AddToVaultSheetState();
}

class _AddToVaultSheetState extends ConsumerState<_AddToVaultSheet> {
  late Future<List<Vault>> _vaults;
  bool _creating = false;
  bool _busy = false;
  final _nameController = TextEditingController();

  LibraryApi get _api => ref.read(libraryApiProvider);

  AddVaultItemRequest get _itemRef => AddVaultItemRequest(
        movieId: widget.seriesId != null ? null : widget.movieId,
        seriesId: widget.seriesId,
      );

  @override
  void initState() {
    super.initState();
    _vaults = _loadVaults();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<List<Vault>> _loadVaults() async {
    final vaults = (await _api.listVaults()) ?? const [];
    // Only vaults the profile may curate.
    return vaults.where((v) => v.isOwner || v.shared).toList();
  }

  Future<void> _addTo(Vault vault) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.addVaultItem(vault.id, _itemRef);
      _done('Added to ${vault.name}');
    } catch (_) {
      _done("Couldn't add to ${vault.name}", error: true);
    }
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final vault = await _api.createVault(CreateVaultRequest(name: name));
      if (vault != null) await _api.addVaultItem(vault.id, _itemRef);
      _done('Added to $name');
    } catch (_) {
      _done("Couldn't create $name", error: true);
    }
  }

  void _done(String message, {bool error = false}) {
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? ArgosyColors.danger : ArgosyColors.panelHi,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FutureBuilder<List<Vault>>(
          future: _vaults,
          builder: (context, snapshot) {
            final vaults = snapshot.data ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add to…',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: ArgosyColors.accent)),
                  )
                else ...[
                  for (final vault in vaults)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_outlined,
                          color: ArgosyColors.accent),
                      title: Text(vault.name),
                      trailing: vault.shared
                          ? const Text('shared',
                              style: TextStyle(color: ArgosyColors.faint))
                          : null,
                      onTap: _busy ? null : () => _addTo(vault),
                    ),
                  if (vaults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No vaults yet.',
                          style: TextStyle(color: ArgosyColors.dim)),
                    ),
                ],
                const Divider(color: ArgosyColors.line),
                if (_creating)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          autofocus: true,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                              hintText: 'New vault name…', isDense: true),
                          onSubmitted: (_) => _createAndAdd(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _createAndAdd,
                        child: const Text('Create'),
                      ),
                    ],
                  )
                else
                  TextButton.icon(
                    onPressed: () => setState(() => _creating = true),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New vault…'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
