import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../widgets/hatch_pattern.dart';
import '../../browse/media_card.dart';
import '../search_providers.dart';

/// Search on the 10-foot screen (ARGY-51 / `TVSearch.dc.html`): the in-app
/// [TvOnScreenKeyboard] drives a query on the left while a live results grid
/// refines on the right — no enter, no system IME. Binds the same
/// [searchQueryProvider] / [searchResultsProvider] the phone search uses.
class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key});

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  String _query = '';

  void _commit() => ref.read(searchQueryProvider.notifier).set(_query.trim());

  void _type(String ch) {
    setState(() => _query += ch);
    _commit();
  }

  void _backspace() {
    if (_query.isEmpty) return;
    setState(() => _query = _query.substring(0, _query.length - 1));
    _commit();
  }

  void _clear() {
    if (_query.isEmpty) return;
    setState(() => _query = '');
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    // Merge films + series into one grid (films first), like the design's single
    // "Results" column.
    final cards = <MediaCard>[
      ...?results.value?.films,
      ...?results.value?.series,
    ];

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      // The keyboard is static (not behind an AsyncView), so it safely holds
      // first-frame focus via autofocusFirst — the remote lands on a key, and
      // Left from the leftmost key reaches the nav rail.
      body: TvStage(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TvNavRail(active: TvSection.search),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 64, 0, 0),
              child: SizedBox(
                width: 540,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THE MANIFEST',
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
                      'Search',
                      style: TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: ArgosyColors.cream,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _QueryField(query: _query, resultCount: cards.length),
                    const SizedBox(height: 26),
                    _SearchKeyboard(
                      onChar: _type,
                      onBackspace: _backspace,
                      onClear: _clear,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'D-pad to a key · OK to add it · Delete to fix a typo',
                      style: TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ArgosyColors.faint2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 64, 64, 0),
                child: _Results(
                  query: _query.trim(),
                  cards: cards,
                  loading: results.isLoading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brass-outlined query display: search glyph, typed text, blinking-less
/// cursor bar, and a trailing result count.
class _QueryField extends StatelessWidget {
  const _QueryField({required this.query, required this.resultCount});

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: ArgosyColors.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ArgosyColors.accentLine, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 24, color: ArgosyColors.accent),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              query.isEmpty ? 'Type to search…' : query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: query.isEmpty ? ArgosyColors.faint : ArgosyColors.cream,
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
          if (query.length >= 2) ...[
            const SizedBox(width: 16),
            Text(
              '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.faint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.cards,
    required this.loading,
  });

  final String query;
  final List<MediaCard> cards;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (query.length < 2) {
      return const _Prompt(
        icon: Icons.travel_explore,
        title: 'Search the Manifest',
        body: 'Spell out a title — results refine as you type, no need to press OK.',
      );
    }
    if (cards.isEmpty) {
      return _Prompt(
        icon: loading ? Icons.hourglass_empty : Icons.search_off,
        title: loading ? 'Searching…' : 'Nothing in the hold',
        body: loading
            ? 'Reading the manifest for "$query".'
            : 'No title matches "$query". Try fewer letters.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ArgosyColors.dim,
            ),
            children: [
              const TextSpan(text: 'Results for '),
              TextSpan(
                text: '"$query"',
                style: const TextStyle(color: ArgosyColors.cream),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 40, right: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 26,
              crossAxisSpacing: 22,
              childAspectRatio: 0.5,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => _ResultTile(card: cards[i]),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.card});

  final MediaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(artworkResolverProvider)(card.posterUrl ?? card.backdropUrl);

    return TvFocusable(
      borderRadius: 13,
      ensureVisibleOnFocus: true,
      onSelect: () => openDetail(context, card.kind, card.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: img != null
                  ? Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const HatchPlaceholder(),
                    )
                  : const HatchPlaceholder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatTitle(card.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ArgosyColors.cream,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${card.kindLabel}${card.year != null ? ' · ${card.year}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ArgosyColors.mute,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact 6-column alphabetical keyboard for Search (`TVSearch.dc.html`).
/// Distinct from the wide [TvOnScreenKeyboard] the pairing/rename flows use:
/// those get the full width, but Search needs a narrow keyboard so the live
/// results grid sits alongside it. Letters + digits, then a Space/Delete/Clear
/// control row; the first key autofocuses so the remote can type on entry.
class _SearchKeyboard extends StatelessWidget {
  const _SearchKeyboard({
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const _key = 72.0;
  static const _gap = 12.0;
  // 6 keys + 5 gaps wide, so letters land in a clean 6-column grid.
  static const _width = _key * 6 + _gap * 5;
  static const _wide = _key * 2 + _gap; // Space / Delete / Clear span 2 columns.

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final (i, ch) in _chars.split('').indexed)
            _CompactKey(
              label: ch.toUpperCase(),
              autofocus: i == 0,
              onSelect: () => onChar(ch),
            ),
          _CompactKey(label: 'Space', width: _wide, onSelect: () => onChar(' ')),
          _CompactKey(label: 'Delete', width: _wide, onSelect: onBackspace),
          _CompactKey(label: 'Clear', width: _wide, onSelect: onClear),
        ],
      ),
    );
  }
}

class _CompactKey extends StatefulWidget {
  const _CompactKey({
    required this.label,
    required this.onSelect,
    this.width = 72,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final double width;
  final bool autofocus;

  @override
  State<_CompactKey> createState() => _CompactKeyState();
}

class _CompactKeyState extends State<_CompactKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final single = widget.label.length == 1;
    return TvFocusable(
      borderRadius: 12,
      scale: 1.12,
      focusOffset: 4,
      autofocus: widget.autofocus,
      onSelect: widget.onSelect,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        width: widget.width,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _focused ? ArgosyColors.accent : ArgosyColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? Colors.transparent : ArgosyColors.line,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontFamily: single ? 'Archivo' : 'HankenGrotesk',
            fontSize: single ? 28 : 16,
            fontWeight: FontWeight.w600,
            color: _focused ? ArgosyColors.ink : ArgosyColors.cream,
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: ArgosyColors.faint),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ArgosyColors.cream,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 420,
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                color: ArgosyColors.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
