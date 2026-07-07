import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
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
    final audioLabels = _audioLabels(audio);
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
                  label: audioLabels[a.id] ?? 'Track ${a.id}',
                  selected: _c.activeAudioTrackId == a.id,
                  onTap: () {
                    _c.selectAudioTrack(a);
                    setState(() {});
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

  // Common ISO-639-1 display names, mirroring the server's language table so the
  // picker reads "Japanese"/"English" rather than the raw code or ffmpeg's
  // generic "audio_N" rendition NAME.
  static const _langNames = <String, String>{
    'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'ja': 'Japanese',
    'zh': 'Chinese', 'ko': 'Korean', 'ar': 'Arabic', 'nl': 'Dutch',
    'pl': 'Polish', 'sv': 'Swedish', 'no': 'Norwegian', 'da': 'Danish',
    'fi': 'Finnish', 'tr': 'Turkish', 'he': 'Hebrew', 'hi': 'Hindi',
    'th': 'Thai', 'vi': 'Vietnamese', 'cs': 'Czech', 'el': 'Greek',
    'hu': 'Hungarian', 'id': 'Indonesian', 'ro': 'Romanian', 'uk': 'Ukrainian',
  };

  String _audioBase(BetterPlayerAsmsAudioTrack a) {
    final lang = a.language;
    if (lang != null && lang.isNotEmpty) {
      return _langNames[lang.toLowerCase()] ?? lang.toUpperCase();
    }
    final label = a.label;
    if (label != null && label.isNotEmpty && !label.startsWith('audio_')) return label;
    return 'Track ${a.id ?? 0}';
  }

  // Builds display labels keyed by track id, de-duplicating when several tracks
  // share a language (e.g. an English dub + English commentary) by suffixing an
  // index — matching the web picker (ARGY-128).
  Map<int?, String> _audioLabels(List<BetterPlayerAsmsAudioTrack> tracks) {
    final counts = <String, int>{};
    final labels = <int?, String>{};
    for (final a in tracks) {
      final base = _audioBase(a);
      counts[base] = (counts[base] ?? 0) + 1;
      labels[a.id] = counts[base]! > 1 ? '$base ${counts[base]}' : base;
    }
    return labels;
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
