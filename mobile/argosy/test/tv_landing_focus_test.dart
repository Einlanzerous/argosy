// The shared landing-focus rule (ARGY-173), tested directly rather than only
// through TV Home — the detail screens depend on it too, and the interesting
// behaviour is in the guard, not in any one screen's layout.

import 'package:argosy/tv/tv_landing_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a screen's primary action: mounts later than the rail and
/// claims focus on mount, exactly as the real ones do.
class _LateAction extends StatefulWidget {
  const _LateAction({required this.node});

  final FocusNode node;

  @override
  State<_LateAction> createState() => _LateActionState();
}

class _LateActionState extends State<_LateAction> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TvLandingFocus.maybeClaim(context, widget.node);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.node, child: const Text('action'));
}

/// A rail that holds focus from the first frame, and an action that appears
/// only once [showAction] flips — the async gap every TV screen has.
Future<void> _pump(
  WidgetTester tester, {
  required FocusNode rail,
  required FocusNode other,
  required FocusNode action,
  required ValueNotifier<bool> showAction,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: TvLandingFocus(
        child: ValueListenableBuilder<bool>(
          valueListenable: showAction,
          builder: (_, show, _) => Column(
            children: [
              Focus(
                focusNode: rail,
                autofocus: true,
                child: const Text('rail'),
              ),
              Focus(focusNode: other, child: const Text('other')),
              if (show) _LateAction(node: action),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  late FocusNode rail;
  late FocusNode other;
  late FocusNode action;
  late ValueNotifier<bool> showAction;

  setUp(() {
    rail = FocusNode(debugLabel: 'rail');
    other = FocusNode(debugLabel: 'other');
    action = FocusNode(debugLabel: 'action');
    showAction = ValueNotifier(false);
  });

  tearDown(() {
    rail.dispose();
    other.dispose();
    action.dispose();
    showAction.dispose();
  });

  testWidgets('claims focus when the viewer has not moved', (tester) async {
    await _pump(
      tester,
      rail: rail,
      other: other,
      action: action,
      showAction: showAction,
    );
    await tester.pump();
    expect(rail.hasFocus, isTrue);

    showAction.value = true;
    await tester.pump();
    await tester.pump();

    expect(action.hasFocus, isTrue);
  });

  testWidgets('stands off once the viewer has moved during the gap', (
    tester,
  ) async {
    await _pump(
      tester,
      rail: rail,
      other: other,
      action: action,
      showAction: showAction,
    );
    await tester.pump();

    // The viewer D-pads elsewhere while the content is still loading.
    other.requestFocus();
    await tester.pump();
    expect(other.hasFocus, isTrue);

    showAction.value = true;
    await tester.pump();
    await tester.pump();

    expect(
      action.hasFocus,
      isFalse,
      reason:
          'claiming here would move the remote off what the viewer aimed at',
    );
    expect(other.hasFocus, isTrue);
  });

  testWidgets('claims unconditionally with no TvLandingFocus ancestor', (
    tester,
  ) async {
    // A screen that never had a landing to protect behaves as it would without
    // the guard, rather than silently never focusing.
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Focus(focusNode: rail, autofocus: true, child: const Text('rail')),
            _LateAction(node: action),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(action.hasFocus, isTrue);
  });
}
