import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';

import '../../theme/argosy_colors.dart';
import 'playback_controller.dart';

/// Bottom sheet for subtitle (and, when the HLS stream carries alternates,
/// audio) track selection. Subtitle choices persist to the device's
/// preferences via the controller.
Future<void> showTrackSheet(BuildContext context, PlaybackController c) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ArgosyColors.panel,
    showDragHandle: true,
    builder: (context) => _TrackSheet(controller: c),
  );
}

class _TrackSheet extends StatefulWidget {
  const _TrackSheet({required this.controller});

  final PlaybackController controller;

  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  PlaybackController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final audio = _c.audioTracks;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Subtitles'),
            _option(
              label: 'Off',
              selected: _c.activeSubtitleId == null,
              onTap: () => _selectSubtitle(null),
            ),
            for (final t in _c.subtitles)
              _option(
                label: _subtitleLabel(t),
                selected: _c.activeSubtitleId == t.id,
                onTap: () => _selectSubtitle(t.id),
              ),
            if (audio.length > 1) ...[
              const SizedBox(height: 8),
              _header('Audio'),
              for (final a in audio)
                _option(
                  label: a.label?.isNotEmpty == true
                      ? a.label!
                      : (a.language ?? 'Track ${a.id}'),
                  selected: false,
                  onTap: () {
                    _c.selectAudioTrack(a);
                    Navigator.of(context).pop();
                  },
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _selectSubtitle(String? id) {
    _c.selectSubtitle(id);
    setState(() {});
  }

  String _subtitleLabel(SubtitleTrack t) {
    final parts = <String>[
      if (t.label.isNotEmpty) t.label else t.language,
      if (t.forced) 'Forced',
    ];
    return parts.join(' · ');
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: ArgosyColors.dim,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _option({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          color: selected ? ArgosyColors.accentHi : ArgosyColors.cream,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: ArgosyColors.accentHi, size: 20)
          : null,
    );
  }
}
