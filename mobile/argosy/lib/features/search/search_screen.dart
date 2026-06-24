import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../widgets/async_view.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import 'search_providers.dart';

/// Search the Manifest — a debounced typeahead against `/api/v1/search`,
/// results grouped into Films and Series.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search films and series…',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _debounce?.cancel();
                      ref.read(searchQueryProvider.notifier).set('');
                      setState(() {});
                    },
                  ),
          ),
        ),
      ),
      body: query.trim().length < 2
          ? const _Hint()
          : AsyncView(
              value: results,
              onRetry: () => ref.invalidate(searchResultsProvider),
              builder: (groups) {
                if (groups.films.isEmpty && groups.series.isEmpty) {
                  return _Empty(query: query);
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    if (groups.films.isNotEmpty)
                      _Group(title: 'Films', cards: groups.films),
                    if (groups.series.isNotEmpty)
                      _Group(title: 'Series', cards: groups.series),
                  ],
                );
              },
            ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.cards});

  final String title;
  final List<MediaCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => MediaPosterCard(card: cards[i], width: 160),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THE MANIFEST',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ArgosyColors.accent,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'What are we\nwatching?',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 14),
          Text(
            'Search the Manifest for any film or series in the hold — by title, '
            'genre, or tag.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'Nothing in the hold matches "$query".',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
