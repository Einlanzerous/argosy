import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../api/api_providers.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_keyboard.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../account/account_providers.dart';
import '../../auth/auth_controller.dart';
import '../../beacon/beacon_providers.dart';
import '../settings_controller.dart';

/// The Bridge on the 10-foot screen (ARGY-51 / `TVSettings.dc.html`): a category
/// list on the left, content on the right. The Fleet category is the centrepiece
/// — a device list with a focusable per-device menu (Rename + Retire), the D-pad
/// replacement for the phone's long-press — using `renameDevice` / `revokeDevice`.
/// Playback + subtitle prefs bind the same [settingsControllerProvider] as the
/// phone settings.
///
/// Focus flows across three full-height columns: nav rail → category list →
/// content (native directional traversal, like every other TV screen).
enum _Category { account, fleet, playback, subtitles, about }

class TvSettingsScreen extends ConsumerStatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  ConsumerState<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends ConsumerState<TvSettingsScreen> {
  _Category _category = _Category.fleet;

  // Fleet menu state: which device's menu is open, whether it's on the retire
  // confirm step, and the rename buffer when renaming.
  String? _menuDeviceId;
  bool _confirmRetire = false;
  String? _renameDeviceId;
  String _renameBuffer = '';

  /// Focus target for the ⋯ button that opened the menu, so closing the menu
  /// hands focus back to it instead of letting it escape to the nav rail.
  final FocusNode _menuButtonFocus = FocusNode(debugLabel: 'device-menu-btn');

  /// Focus target for the open menu's primary action (Rename, or Confirm retire
  /// on the confirm step), driven on open so the remote lands on the action
  /// rather than the close button.
  final FocusNode _menuActionFocus = FocusNode(debugLabel: 'device-menu-action');

  /// Focus target for the rename keyboard's first key. Swapping the whole
  /// content pane into rename mode removes the focused Rename chip, so frame-1
  /// autofocus loses the race to the route scope — we drive focus here instead.
  final FocusNode _renameKeyFocus = FocusNode(debugLabel: 'rename-first-key');

  /// One persistent focus node per category row. The active category autofocuses
  /// on entry (so the remote lands in the list, not the device content), and
  /// LEFT from the content column hops back to the active row — the category
  /// column is short, so native LEFT from a low content item would otherwise
  /// overshoot it and land on the nav rail.
  late final Map<_Category, FocusNode> _catNodes = {
    for (final c in _Category.values) c: FocusNode(debugLabel: 'cat-$c'),
  };

  @override
  void dispose() {
    _menuButtonFocus.dispose();
    _menuActionFocus.dispose();
    _renameKeyFocus.dispose();
    for (final n in _catNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// LEFT inside the content column: move within content if possible, else hop
  /// back to the active category (never overshoot to the nav rail).
  KeyEventResult _onContentKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final moved = FocusManager.instance.primaryFocus
              ?.focusInDirection(TraversalDirection.left) ??
          false;
      if (!moved) _catNodes[_category]?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Pull focus onto [node] after the next frame lays it out.
  void _focusAfterFrame(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });

  void _focusMenuAction() => _focusAfterFrame(_menuActionFocus);

  void _selectCategory(_Category c) => setState(() {
        _category = c;
        _menuDeviceId = null;
        _confirmRetire = false;
        _renameDeviceId = null;
      });

  void _closeMenu() {
    setState(() {
      _menuDeviceId = null;
      _confirmRetire = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuButtonFocus.context != null) {
        _menuButtonFocus.requestFocus();
      }
    });
  }

  Future<void> _retire(Device device) async {
    try {
      await ref.read(authApiProvider).revokeDevice(device.id);
      ref.invalidate(fleetDevicesProvider);
    } catch (_) {
      _snack("Couldn't retire that device.");
    }
    if (mounted) _closeMenu();
  }

  Future<void> _saveRename() async {
    final id = _renameDeviceId;
    final name = _renameBuffer.trim();
    if (id == null || name.isEmpty) return;
    try {
      await ref.read(authApiProvider).renameDevice(id, DeviceRenameRequest(name: name));
      ref.invalidate(fleetDevicesProvider);
    } catch (_) {
      _snack("Couldn't rename that device.");
    }
    if (mounted) setState(() => _renameDeviceId = null);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            // Nav rail does NOT autofocus here — the active category does, so the
            // remote lands in the category list rather than the device content.
            const TvNavRail(active: TvSection.settings),
            _CategoryColumn(
              active: _category,
              nodes: _catNodes,
              onSelect: _selectCategory,
            ),
            // Contain content traversal so LEFT redirects to the category column
            // at the left edge (see _onContentKey).
            Expanded(
              child: FocusTraversalGroup(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onContentKey,
                  child: _content(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_renameDeviceId != null) {
      return _RenamePanel(
        value: _renameBuffer,
        firstKeyFocus: _renameKeyFocus,
        onChar: (ch) => setState(() => _renameBuffer += ch),
        onBackspace: () => setState(() => _renameBuffer = _renameBuffer.isEmpty
            ? ''
            : _renameBuffer.substring(0, _renameBuffer.length - 1)),
        onClear: () => setState(() => _renameBuffer = ''),
        onSave: _saveRename,
        onCancel: () => setState(() => _renameDeviceId = null),
      );
    }
    return switch (_category) {
      _Category.account => _AccountContent(),
      _Category.fleet => _fleetContent(),
      _Category.playback => _PlaybackContent(),
      _Category.subtitles => _SubtitlesContent(),
      _Category.about => _AboutContent(),
    };
  }

  Widget _fleetContent() {
    final devices = ref.watch(fleetDevicesProvider);
    final selfId = ref.watch(selfDeviceIdProvider).value;

    return _ContentScroll(
      title: 'Fleet · Devices',
      subtitle: 'Everything paired to your household server.',
      children: [
        const _FleetBanner(),
        const SizedBox(height: 24),
        ...devices.when(
          loading: () => [const _Loading()],
          error: (_, _) => [
            const _Note("Couldn't load your Fleet right now."),
          ],
          data: (list) => [
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _DeviceCard(
                  device: d,
                  isSelf: d.id == selfId,
                  menuOpen: _menuDeviceId == d.id,
                  confirmRetire: _confirmRetire,
                  menuButtonFocus: _menuDeviceId == d.id ? _menuButtonFocus : null,
                  menuActionFocus: _menuActionFocus,
                  onOpenMenu: () {
                    setState(() {
                      _menuDeviceId = d.id;
                      _confirmRetire = false;
                    });
                    _focusMenuAction();
                  },
                  onCloseMenu: _closeMenu,
                  onRename: () {
                    setState(() {
                      _renameDeviceId = d.id;
                      _renameBuffer = d.name;
                      _menuDeviceId = null;
                    });
                    _focusAfterFrame(_renameKeyFocus);
                  },
                  onAskRetire: () {
                    setState(() => _confirmRetire = true);
                    _focusMenuAction();
                  },
                  onConfirmRetire: () => _retire(d),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// --- Category list -----------------------------------------------------------

class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.active,
    required this.nodes,
    required this.onSelect,
  });

  final _Category active;
  final Map<_Category, FocusNode> nodes;
  final ValueChanged<_Category> onSelect;

  static const _items = <(_Category, IconData, String)>[
    (_Category.account, Icons.account_circle_outlined, 'Account'),
    (_Category.fleet, Icons.dvr_outlined, 'Fleet · Devices'),
    (_Category.playback, Icons.play_circle_outline, 'Playback'),
    (_Category.subtitles, Icons.subtitles_outlined, 'Subtitles & Audio'),
    (_Category.about, Icons.info_outline, 'About Argosy'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      decoration: const BoxDecoration(
        color: ArgosyColors.bg2,
        border: Border(right: BorderSide(color: ArgosyColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(26, 56, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SETTINGS',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
              color: ArgosyColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bridge',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: ArgosyColors.cream,
            ),
          ),
          const SizedBox(height: 30),
          for (final (cat, icon, label) in _items) ...[
            _CategoryRow(
              icon: icon,
              label: label,
              active: cat == active,
              focusNode: nodes[cat],
              autofocus: cat == active,
              onSelect: () => onSelect(cat),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.onSelect,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 11,
      scale: 1.03,
      focusOffset: 3,
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      // Switch the content as soon as the category is focused (focus-follows,
      // the expected 10-foot pattern) — OK still works, it's just redundant.
      onFocusChange: (focused) {
        if (focused && !active) onSelect();
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          if (active)
            Positioned(
              left: 0,
              child: Container(
                width: 4,
                height: 22,
                decoration: const BoxDecoration(
                  color: ArgosyColors.accent,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: active ? ArgosyColors.accentBg2 : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 21,
                    color: active ? ArgosyColors.accent : ArgosyColors.dim),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: active ? ArgosyColors.accent : ArgosyColors.soft2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Shared content shell ----------------------------------------------------

/// A scrolling content pane with a big title + subtitle header, used by every
/// settings category.
class _ContentScroll extends StatelessWidget {
  const _ContentScroll({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(46, 64, 64, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: ArgosyColors.cream,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ArgosyColors.dim,
            ),
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

// --- Fleet -------------------------------------------------------------------

class _FleetBanner extends StatelessWidget {
  const _FleetBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: ArgosyColors.accentBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: ArgosyColors.accentLine),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_alt, size: 20, color: ArgosyColors.accent),
          const SizedBox(width: 13),
          const Expanded(
            child: Text(
              'Every device in your Fleet shares one playhead. Open a device menu '
              'to rename it, or retire it to drop it from sync — no long-press needed.',
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.accentSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isSelf,
    required this.menuOpen,
    required this.confirmRetire,
    required this.menuButtonFocus,
    required this.menuActionFocus,
    required this.onOpenMenu,
    required this.onCloseMenu,
    required this.onRename,
    required this.onAskRetire,
    required this.onConfirmRetire,
  });

  final Device device;
  final bool isSelf;
  final bool menuOpen;
  final bool confirmRetire;
  final FocusNode? menuButtonFocus;
  final FocusNode menuActionFocus;
  final VoidCallback onOpenMenu;
  final VoidCallback onCloseMenu;
  final VoidCallback onRename;
  final VoidCallback onAskRetire;
  final VoidCallback onConfirmRetire;

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
    final type = (device.platform == null || device.platform!.isEmpty)
        ? 'Device'
        : device.platform![0].toUpperCase() + device.platform!.substring(1);
    final seen = isSelf ? 'this device' : formatRelativeTime(device.lastSeenAt);

    return Container(
      decoration: BoxDecoration(
        color: menuOpen ? ArgosyColors.panelHi : ArgosyColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: menuOpen || isSelf ? ArgosyColors.accentLine : ArgosyColors.line,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: ArgosyColors.accentBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_icon, size: 24, color: ArgosyColors.accent),
                ),
                const SizedBox(width: 20),
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
                              style: const TextStyle(
                                fontFamily: 'Archivo',
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: ArgosyColors.cream,
                              ),
                            ),
                          ),
                          if (isSelf) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: ArgosyColors.accentBg2,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'THIS TV',
                                style: TextStyle(
                                  fontFamily: 'Archivo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: ArgosyColors.accentSoft,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$type · last seen $seen',
                        style: const TextStyle(
                          fontFamily: 'HankenGrotesk',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: ArgosyColors.mute,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _MenuButton(
                  focusNode: menuButtonFocus,
                  active: menuOpen,
                  onSelect: menuOpen ? onCloseMenu : onOpenMenu,
                ),
              ],
            ),
          ),
          if (menuOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _DeviceMenu(
                isSelf: isSelf,
                confirmRetire: confirmRetire,
                primaryFocus: menuActionFocus,
                onRename: onRename,
                onAskRetire: onAskRetire,
                onConfirmRetire: onConfirmRetire,
                onCancel: onCloseMenu,
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.focusNode,
    required this.active,
    required this.onSelect,
  });

  final FocusNode? focusNode;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 11,
      focusNode: focusNode,
      onSelect: onSelect,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ArgosyColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? Colors.transparent : ArgosyColors.line2,
            width: 1.5,
          ),
        ),
        child: Icon(
          active ? Icons.close : Icons.more_horiz,
          size: 22,
          color: active ? ArgosyColors.ink : ArgosyColors.dim,
        ),
      ),
    );
  }
}

/// The inline per-device action menu (Rename / Retire), the D-pad replacement
/// for the phone's long-press. Retire is a two-step confirm so a stray OK can't
/// drop a device.
class _DeviceMenu extends StatelessWidget {
  const _DeviceMenu({
    required this.isSelf,
    required this.confirmRetire,
    required this.primaryFocus,
    required this.onRename,
    required this.onAskRetire,
    required this.onConfirmRetire,
    required this.onCancel,
  });

  final bool isSelf;
  final bool confirmRetire;
  final FocusNode primaryFocus;
  final VoidCallback onRename;
  final VoidCallback onAskRetire;
  final VoidCallback onConfirmRetire;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (confirmRetire) {
      return Row(
        children: [
          const Expanded(
            child: Text(
              'Retire this device from your Fleet? It has to pair again to return.',
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.soft,
              ),
            ),
          ),
          const SizedBox(width: 16),
          _MenuChip(
            icon: Icons.logout,
            label: 'Confirm retire',
            danger: true,
            focusNode: primaryFocus,
            onSelect: onConfirmRetire,
          ),
          const SizedBox(width: 12),
          _MenuChip(icon: Icons.close, label: 'Cancel', onSelect: onCancel),
        ],
      );
    }
    return Row(
      children: [
        _MenuChip(
          icon: Icons.edit_outlined,
          label: 'Rename',
          focusNode: primaryFocus,
          onSelect: onRename,
        ),
        const SizedBox(width: 12),
        if (isSelf)
          const Expanded(
            child: Text(
              'Sign out from Account to retire this TV.',
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.faint,
              ),
            ),
          )
        else
          _MenuChip(
            icon: Icons.logout,
            label: 'Retire from Fleet',
            danger: true,
            onSelect: onAskRetire,
          ),
      ],
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.danger = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;

  /// When the menu opens, the parent drives focus to its primary action (Rename
  /// / Confirm retire) through this node, so the remote lands on it instead of
  /// the close button.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final color = danger ? ArgosyColors.danger : ArgosyColors.accent;
    return TvFocusable(
      focusNode: focusNode,
      ensureVisibleOnFocus: true,
      borderRadius: 10,
      scale: 1.05,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: danger ? const Color(0x1FE08A6E) : ArgosyColors.accentBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-pane rename flow: a read-only field + on-screen keyboard + Save/Cancel.
class _RenamePanel extends StatelessWidget {
  const _RenamePanel({
    required this.value,
    required this.firstKeyFocus,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    required this.onSave,
    required this.onCancel,
  });

  final String value;
  final FocusNode firstKeyFocus;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(46, 64, 64, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rename device',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: ArgosyColors.cream,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This name shows up across your Fleet.',
            style: TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ArgosyColors.dim,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 620,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: ArgosyColors.panel2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ArgosyColors.accentLine, width: 1.5),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    value.isEmpty ? 'Device name' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: value.isEmpty ? ArgosyColors.faint : ArgosyColors.cream,
                    ),
                  ),
                ),
                Container(
                  width: 3,
                  height: 30,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: ArgosyColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          TvOnScreenKeyboard(
            autofocusFirst: true,
            firstKeyFocusNode: firstKeyFocus,
            onChar: onChar,
            onBackspace: onBackspace,
            onClear: onClear,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _MenuChip(icon: Icons.check, label: 'Save name', onSelect: onSave),
              const SizedBox(width: 14),
              _MenuChip(icon: Icons.close, label: 'Cancel', onSelect: onCancel),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Playback ----------------------------------------------------------------

class _PlaybackContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    return settings.when(
      loading: () => const _Loading(),
      error: (_, _) => const _Note("Couldn't load preferences."),
      data: (data) => _ContentScroll(
        title: 'Playback',
        subtitle: 'How episodes roll and how the Bridge is laid out.',
        children: [
          _ToggleRow(
            label: 'Auto-play next episode',
            subtitle: 'Roll into the next episode with an Up Next countdown.',
            value: data.device.seriesAutoAdvance ?? true,
            onToggle: () => _guard(context,
                () => ctrl.setSeriesAutoAdvance(!(data.device.seriesAutoAdvance ?? true))),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Home layout'),
          _OptionPicker<UserPreferencesHomeLayoutEnum>(
            selected: data.user.homeLayout,
            options: const [
              ('Focused', UserPreferencesHomeLayoutEnum.focused),
              ('Discovery', UserPreferencesHomeLayoutEnum.discovery),
            ],
            onSelect: (v) => _guard(context, () => ctrl.setHomeLayout(v)),
          ),
        ],
      ),
    );
  }
}

// --- Subtitles & Audio -------------------------------------------------------

const _subtitleLanguages = <(String, String?)>[
  ('Automatic', null),
  ('English', 'en'),
  ('Spanish', 'es'),
  ('French', 'fr'),
  ('German', 'de'),
  ('Italian', 'it'),
  ('Japanese', 'ja'),
  ('Korean', 'ko'),
  ('Chinese', 'zh'),
];

const _captionSizes = <(String, double)>[
  ('Small', 0.85),
  ('Default', 1.0),
  ('Large', 1.25),
  ('X-Large', 1.5),
];

const _captionColors = <(String, String)>[
  ('White', '#FFFFFF'),
  ('Cream', '#EAEAE5'),
  ('Yellow', '#F1C40F'),
  ('Cyan', '#22D3EE'),
  ('Green', '#A3E635'),
];

const _captionBackgrounds = <(String, DevicePreferencesCaptionBackgroundEnum)>[
  ('Translucent', DevicePreferencesCaptionBackgroundEnum.translucent),
  ('Solid', DevicePreferencesCaptionBackgroundEnum.solid),
  ('None', DevicePreferencesCaptionBackgroundEnum.none),
];

const _captionPositions = <(String, DevicePreferencesCaptionPositionEnum)>[
  ('Bottom', DevicePreferencesCaptionPositionEnum.bottom),
  ('Raised', DevicePreferencesCaptionPositionEnum.raised),
  ('Higher', DevicePreferencesCaptionPositionEnum.higher),
];

/// Vertical alignment of the caption sample in the preview frame, matching the
/// position presets (bottom near the edge → higher up the frame).
double _previewAlignY(DevicePreferencesCaptionPositionEnum? pos) => switch (pos) {
      DevicePreferencesCaptionPositionEnum.bottom => 0.86,
      DevicePreferencesCaptionPositionEnum.higher => 0.30,
      _ => 0.62, // raised (default)
    };

class _SubtitlesContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    return settings.when(
      loading: () => const _Loading(),
      error: (_, _) => const _Note("Couldn't load preferences."),
      data: (data) {
        final dev = data.device;
        return _ContentScroll(
          title: 'Subtitles & Audio',
          subtitle: 'Default tracks and how captions look on this TV.',
          children: [
            // Live preview — reflects size/colour/background as they change.
            _CaptionPreview(
              scale: (dev.captionScale ?? 1.0).toDouble(),
              colorHex: dev.captionColor ?? '#FFFFFF',
              background: dev.captionBackground ??
                  DevicePreferencesCaptionBackgroundEnum.translucent,
              position: dev.captionPosition ??
                  DevicePreferencesCaptionPositionEnum.raised,
            ),
            const SizedBox(height: 22),
            _ToggleRow(
              label: 'Subtitles on by default',
              subtitle: 'Show a subtitle track automatically when one matches.',
              value: dev.subtitleEnabled,
              onToggle: () => _guard(
                  context, () => ctrl.setSubtitlesEnabled(!dev.subtitleEnabled)),
            ),
            const SizedBox(height: 14),
            _SectionLabel('Subtitle language'),
            _OptionPicker<String?>(
              selected: dev.subtitleLanguage,
              options: _subtitleLanguages,
              onSelect: (v) => _guard(context, () => ctrl.setSubtitleLanguage(v)),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Caption size'),
            _OptionPicker<double>(
              selected: (dev.captionScale ?? 1.0).toDouble(),
              options: _captionSizes,
              onSelect: (v) => _guard(context, () => ctrl.setCaptionScale(v)),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Caption colour'),
            _CaptionColourPicker(
              selected: (dev.captionColor ?? '#FFFFFF').toUpperCase(),
              onSelect: (v) => _guard(context, () => ctrl.setCaptionColor(v)),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Caption background'),
            _OptionPicker<DevicePreferencesCaptionBackgroundEnum>(
              selected: dev.captionBackground ??
                  DevicePreferencesCaptionBackgroundEnum.translucent,
              options: _captionBackgrounds,
              onSelect: (v) => _guard(context, () => ctrl.setCaptionBackground(v)),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Caption position'),
            _OptionPicker<DevicePreferencesCaptionPositionEnum>(
              selected: dev.captionPosition ??
                  DevicePreferencesCaptionPositionEnum.raised,
              options: _captionPositions,
              onSelect: (v) => _guard(context, () => ctrl.setCaptionPosition(v)),
            ),
          ],
        );
      },
    );
  }
}

/// A live caption sample that reflects the current size / colour / background,
/// over a faux video frame, so the choices below read as what you'll see.
class _CaptionPreview extends StatelessWidget {
  const _CaptionPreview({
    required this.scale,
    required this.colorHex,
    required this.background,
    required this.position,
  });

  final double scale;
  final String colorHex;
  final DevicePreferencesCaptionBackgroundEnum background;
  final DevicePreferencesCaptionPositionEnum position;

  @override
  Widget build(BuildContext context) {
    final color = _hex(colorHex);
    final hasBg = background != DevicePreferencesCaptionBackgroundEnum.none;
    final bgColor = background == DevicePreferencesCaptionBackgroundEnum.solid
        ? Colors.black
        : const Color(0xB3000000); // translucent

    final caption = Text(
      'She glanced back at the harbour lights.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'HankenGrotesk',
        fontSize: 30 * scale,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );

    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ArgosyColors.line),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF223040), Color(0xFF12161B)],
        ),
      ),
      child: Stack(
        children: [
          // A muted eyebrow so it reads as a preview, not real content.
          const Positioned(
            top: 16,
            left: 20,
            child: Text(
              'PREVIEW',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Color(0x66EAEAE5),
              ),
            ),
          ),
          Align(
            alignment: Alignment(0, _previewAlignY(position)),
            child: hasBg
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: caption,
                  )
                : caption,
          ),
        ],
      ),
    );
  }
}

/// Caption-colour picker — focusable swatches of the actual colour (not the
/// name), with a brass ring on the selected one.
class _CaptionColourPicker extends StatelessWidget {
  const _CaptionColourPicker({required this.selected, required this.onSelect});

  /// Uppercase `#RRGGBB`.
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final (_, hex) in _captionColors)
          _ColourSwatch(
            hex: hex,
            selected: hex.toUpperCase() == selected,
            onSelect: () => onSelect(hex.toUpperCase()),
          ),
      ],
    );
  }
}

class _ColourSwatch extends StatelessWidget {
  const _ColourSwatch({
    required this.hex,
    required this.selected,
    required this.onSelect,
  });

  final String hex;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final color = _hex(hex);
    return TvFocusable(
      borderRadius: 30,
      onSelect: onSelect,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            // Selected gets a brass ring; otherwise a hairline so light swatches
            // still read against the panel.
            color: selected ? ArgosyColors.accent : ArgosyColors.line2,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 24, color: _onColor(color))
            : null,
      ),
    );
  }
}

// --- Account -----------------------------------------------------------------

class _AccountContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseUrlProvider);
    return _ContentScroll(
      title: 'Account',
      subtitle: 'The server this TV is paired to, and how to switch it.',
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          decoration: BoxDecoration(
            color: ArgosyColors.panel,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: ArgosyColors.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, size: 22, color: ArgosyColors.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Household server',
                      style: TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ArgosyColors.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      base.isEmpty ? 'Not set' : base,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ArgosyColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActionRow(
          icon: Icons.switch_account_outlined,
          label: 'Switch profile or server',
          subtitle: 'Sign out so you can pick a different profile or address, then re-pair.',
          onSelect: () => _confirmSignOut(
            context,
            ref,
            title: 'Switch profile or server?',
            body: 'This signs the TV out so you can pick a different profile or '
                'server address, then pair again.',
            confirm: 'Continue',
          ),
        ),
        const SizedBox(height: 12),
        _ActionRow(
          icon: Icons.logout,
          label: 'Sign out',
          subtitle: 'Drop this TV from the Fleet until it pairs again.',
          danger: true,
          onSelect: () => _confirmSignOut(
            context,
            ref,
            title: 'Sign out?',
            body: "You'll need to sign in and pair this TV again to watch.",
            confirm: 'Sign out',
          ),
        ),
      ],
    );
  }
}

// --- About -------------------------------------------------------------------

/// App version/build for the About screen. Loaded once from the platform.
final _packageInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class _AboutContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_packageInfoProvider);
    final version = info.value;

    return _ContentScroll(
      title: 'About Argosy',
      subtitle: 'Your household media, on the big screen.',
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ArgosyColors.panel,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: ArgosyColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Argosy for Android TV',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: ArgosyColors.cream,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Browse, search, and play everything in your household hold — '
                'with one shared playhead across your whole Fleet.',
                style: TextStyle(
                  fontFamily: 'HankenGrotesk',
                  fontSize: 17,
                  height: 1.5,
                  color: ArgosyColors.dim,
                ),
              ),
              const SizedBox(height: 22),
              const Divider(color: ArgosyColors.line, height: 1),
              const SizedBox(height: 18),
              _AboutRow(
                label: 'Version',
                value: version == null
                    ? '…'
                    : '${version.version} (${version.buildNumber})',
              ),
              const SizedBox(height: 12),
              _AboutRow(
                label: 'Server',
                value: ref.watch(baseUrlProvider),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ArgosyColors.accent,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: ArgosyColors.cream,
            ),
          ),
        ),
      ],
    );
  }
}

// --- Reusable focusable rows -------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 2),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Archivo',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: ArgosyColors.faint,
          ),
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onToggle,
  });

  final String label;
  final String subtitle;
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 13,
      scale: 1.02,
      focusOffset: 4,
      onSelect: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: ArgosyColors.panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: ArgosyColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: ArgosyColors.cream,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 14,
                      color: ArgosyColors.dim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            _Switch(value: value),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 56,
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? ArgosyColors.accent : ArgosyColors.line3,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: ArgosyColors.cream,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of selectable option chips (the D-pad-friendly replacement
/// for a dropdown). Each chip is focusable; the selected one is brass-filled.
class _OptionPicker<T> extends StatelessWidget {
  const _OptionPicker({
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final T selected;
  final List<(String, T)> options;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, value) in options)
          _OptionChip(
            label: label,
            selected: value == selected,
            onSelect: () => onSelect(value),
          ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 11,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? ArgosyColors.accentBg2 : ArgosyColors.panel,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? ArgosyColors.accentLine : ArgosyColors.line2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'HankenGrotesk',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: selected ? ArgosyColors.accent : ArgosyColors.soft,
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onSelect,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onSelect;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? ArgosyColors.danger : ArgosyColors.cream;
    return TvFocusable(
      borderRadius: 13,
      scale: 1.02,
      focusOffset: 4,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: ArgosyColors.panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: danger ? ArgosyColors.danger.withValues(alpha: 0.35) : ArgosyColors.line,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: danger ? ArgosyColors.danger : ArgosyColors.accent),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 14,
                      color: ArgosyColors.dim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Small shared bits -------------------------------------------------------

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2, color: ArgosyColors.accent),
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'HankenGrotesk',
            fontSize: 17,
            color: ArgosyColors.dim,
          ),
        ),
      );
}

// --- Helpers -----------------------------------------------------------------

/// Parses a `#RRGGBB` caption-colour hex into a [Color].
Color _hex(String hex) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFFFFFFF);
}

/// Black or white, whichever reads on [bg] (for the selected swatch's check).
Color _onColor(Color bg) =>
    bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

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

Future<void> _confirmSignOut(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String body,
  required String confirm,
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
          child: Text(confirm, style: const TextStyle(color: ArgosyColors.accentHi)),
        ),
      ],
    ),
  );
  if (ok ?? false) {
    await ref.read(authControllerProvider.notifier).signOut();
  }
}
