import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';

/// "Your labels" editor — the profile's custom labels on a film or series.
/// Exactly one of [movieId] / [seriesId] identifies the title. Edits are
/// optimistic; a failed call rolls the chip back.
class LabelEditor extends ConsumerStatefulWidget {
  const LabelEditor({
    super.key,
    this.movieId,
    this.seriesId,
    this.initial = const [],
  }) : assert(movieId != null || seriesId != null,
            'LabelEditor needs a movieId or seriesId');

  final String? movieId;
  final String? seriesId;
  final List<String> initial;

  @override
  ConsumerState<LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends ConsumerState<LabelEditor> {
  late List<String> _labels = [...widget.initial];
  bool _adding = false;
  bool _busy = false;
  final _controller = TextEditingController();

  LibraryApi get _api => ref.read(libraryApiProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = widget.seriesId != null
          ? await _api.addSeriesLabel(
              widget.seriesId!, AddLabelRequest(label: value))
          : await _api.addItemLabel(
              widget.movieId!, AddLabelRequest(label: value));
      if (mounted) setState(() => _labels = updated ?? _labels);
    } catch (_) {
      // Leave the list as-is on failure.
    } finally {
      _controller.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _adding = false;
        });
      }
    }
  }

  Future<void> _remove(String label) async {
    setState(() => _labels = _labels.where((l) => l != label).toList());
    try {
      if (widget.seriesId != null) {
        await _api.removeSeriesLabel(widget.seriesId!, label);
      } else {
        await _api.removeItemLabel(widget.movieId!, label);
      }
    } catch (_) {
      if (mounted) setState(() => _labels = [..._labels, label]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR LABELS',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ArgosyColors.faint,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final label in _labels)
              Chip(
                label: Text(label),
                onDeleted: () => _remove(label),
                deleteIcon: const Icon(Icons.close, size: 15),
                backgroundColor: tokens.accentWash,
                side: BorderSide(color: tokens.accentLine),
                labelStyle: const TextStyle(color: ArgosyColors.accentHi),
              ),
            if (_adding)
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                      hintText: 'label…', isDense: true),
                  onSubmitted: (_) => _add(),
                  onTapOutside: (_) {
                    if (_controller.text.trim().isEmpty) {
                      setState(() => _adding = false);
                    }
                  },
                ),
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Label'),
                onPressed: () => setState(() => _adding = true),
                side: BorderSide(color: tokens.line2),
              ),
          ],
        ),
      ],
    );
  }
}
