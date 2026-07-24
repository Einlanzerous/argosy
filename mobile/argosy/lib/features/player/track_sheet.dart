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

  // Preferred-language fold (ARGY-154): only preferred-language tracks (plus
  // the active one) show by default; the rest sit behind "More options".
  bool _showAllSubs = false;
  bool _showAllAudio = false;

  bool _preferred(String? lang) {
    final prefs = _c.preferredLanguages;
    if (prefs.isEmpty) return true;
    return prefs.contains((lang ?? '').toLowerCase().split('-').first);
  }

  /// Splits tracks into (default view, folded); a list with no preferred
  /// match shows everything — the fold is a preference, not a filter.
  (List<T>, List<T>) _fold<T>(List<T> tracks, bool Function(T) inDefault) {
    final main = <T>[];
    final more = <T>[];
    for (final t in tracks) {
      (inDefault(t) ? main : more).add(t);
    }
    if (main.isEmpty) return (tracks, <T>[]);
    return (main, more);
  }

  @override
  Widget build(BuildContext context) {
    final audio = _c.audioTracks;
    final audioLabels = _audioLabels(audio);
    final (subsMain, subsMore) = _fold(
      _c.subtitles,
      (t) => _preferred(t.language) || _c.activeSubtitleId == t.id,
    );
    final (audioMain, audioMore) = _fold(
      audio,
      (a) => _preferred(a.language) || _c.activeAudioTrackId == a.id,
    );
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
            for (final t in [...subsMain, if (_showAllSubs) ...subsMore])
              _option(
                label: _subtitleLabel(t),
                selected: _c.activeSubtitleId == t.id,
                onTap: () => _selectSubtitle(t.id),
              ),
            if (subsMore.isNotEmpty)
              _moreOption(
                count: subsMore.length,
                open: _showAllSubs,
                onTap: () => setState(() => _showAllSubs = !_showAllSubs),
              ),
            if (audio.length > 1) ...[
              const SizedBox(height: 8),
              _header('Audio'),
              for (final a in [...audioMain, if (_showAllAudio) ...audioMore])
                _option(
                  label: audioLabels[a.id] ?? 'Track ${a.id}',
                  selected: _c.activeAudioTrackId == a.id,
                  onTap: () {
                    _c.selectAudioTrack(a);
                    setState(() {});
                  },
                ),
              if (audioMore.isNotEmpty)
                _moreOption(
                  count: audioMore.length,
                  open: _showAllAudio,
                  onTap: () => setState(() => _showAllAudio = !_showAllAudio),
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

  /// The fold's expander row — dimmer than a real track so it reads as a
  /// control, not a selectable option.
  Widget _moreOption({
    required int count,
    required bool open,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      title: Text(
        open ? 'Fewer options' : 'More options ($count)',
        style: const TextStyle(color: ArgosyColors.dim, fontSize: 14),
      ),
      trailing: Icon(
        open ? Icons.expand_less : Icons.expand_more,
        color: ArgosyColors.dim,
        size: 20,
      ),
    );
  }

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
