import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BallisticNestedScrollActivity', () {
    // The simulation starts at totalPixels, which includes any borrowed bounce.
    // The first movement should add only the difference to the visible offset of the child.
    for (final borrowed in [-40.0, 40.0]) {
      testWidgets('uses totalPixels for the first move with $borrowed borrowed pixels', (tester) async {
        final context = await _pumpBallisticScroll(tester, lentPixels: borrowed);

        // Move 30 pixels beyond the initial simulation position.
        expect(context.activity.applyMoveTo(200 + borrowed + 30), isTrue);

        // Borrowed pixels must not be added to the movement of the child again.
        expect(context.position.pixels, 230);
        expect(context.position.lentPixels, borrowed);
        expect(context.position.totalPixels, 230 + borrowed);
      });
    }

    // Consecutive simulation samples represent absolute positions, not movement amounts.
    // After each microtask checkpoint, only the difference from the previous sample should move the child.
    // Parent consumption must not cause that consumed distance to be applied again on the next update.
    for (final fraction in [0.0, 0.5, 1.0]) {
      testWidgets('applies consecutive deltas when the parent consumes $fraction', (tester) async {
        final availableOffsets = <double>[];
        final context = await _pumpBallisticScroll(
          tester,
          onPreScroll: (available, _) {
            availableOffsets.add(available);
            return available * fraction;
          },
        );

        // The first sample advances by 30 pixels.
        expect(context.activity.applyMoveTo(230), isTrue);
        expect(context.position.pixels, 200 + 30 * (1 - fraction));
        await Future<void>.value();

        // The second sample advances by 20 more, regardless of parent consumption.
        expect(context.activity.applyMoveTo(250), isTrue);
        expect(context.position.pixels, 200 + 50 * (1 - fraction));
        expect(availableOffsets, [-30, -20]);
      });
    }

    // Repeating the last committed simulation sample has no movement to apply.
    // It should preserve the scroll offset of the child and avoid invoking the parent consumer again.
    testWidgets('ignores a repeated simulation sample', (tester) async {
      var calls = 0;
      final context = await _pumpBallisticScroll(
        tester,
        onPreScroll: (_, _) {
          calls++;
          return 0;
        },
      );
      context.activity.applyMoveTo(230);
      await Future<void>.value();

      expect(context.activity.applyMoveTo(230), isTrue);
      expect(context.position.pixels, 230);
      expect(calls, 1);
    });

    // A simulation can reverse direction while recovering from a bounce.
    // A smaller sample after a larger one must move the child backward by their difference.
    testWidgets('preserves the sign when simulation movement reverses', (tester) async {
      final context = await _pumpBallisticScroll(tester);
      context.activity.applyMoveTo(250);
      await Future<void>.value();

      expect(context.activity.applyMoveTo(220), isTrue);
      expect(context.position.pixels, 220);
    });

    // Samples received before microtasks run share the previous committed baseline.
    // When the queued updates finish, the latest sample must become the next baseline.
    // Let the parent consume everything so this test isolates the offsets sent to it.
    testWidgets('commits the latest sample after pending microtasks', (tester) async {
      final availableOffsets = <double>[];
      final context = await _pumpBallisticScroll(
        tester,
        onPreScroll: (available, _) {
          availableOffsets.add(available);
          return available;
        },
      );

      context.activity.applyMoveTo(230);
      context.activity.applyMoveTo(250);
      expect(availableOffsets, [-30, -50]);
      await Future<void>.value();

      // The next delta is measured from 250, rather than 200 or 230.
      expect(context.activity.applyMoveTo(270), isTrue);
      expect(availableOffsets, [-30, -50, -20]);
      expect(context.position.pixels, 200);
    });

    // The activity tells its caller whether movement can continue using the returned overflow.
    // Unconsumed overflow should return false; full post-scroll consumption should return true.
    for (final consumeOverflow in [false, true]) {
      testWidgets('reports continuation when overflow consumption is $consumeOverflow', (tester) async {
        final context = await _pumpBallisticScroll(
          tester,
          onPostScroll: (available, _) => consumeOverflow ? available : 0,
        );
        final boundary = context.position.maxScrollExtent;

        expect(context.activity.applyMoveTo(boundary + 40), consumeOverflow);
        expect(context.position.pixels, boundary);
      });
    }
  });
}

/// Mounts a real scroll position with a manually sampled ballistic activity.
/// Tests flush microtasks without pumping frames so the ticker cannot add extra samples.
Future<_TestContext> _pumpBallisticScroll(
  WidgetTester tester, {
  double lentPixels = 0,
  NestedScrollListener? onPreScroll,
  NestedScrollListener? onPostScroll,
}) async {
  final controller = NestedScrollController(initialScrollOffset: 200);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  await tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: NestedScrollConnection(
            onPreScroll: onPreScroll,
            onPostScroll: onPostScroll,
            child: SingleChildScrollView(
              controller: controller,
              physics: const ClampingScrollPhysics(),
              child: const SizedBox(height: 1000),
            ),
          ),
        ),
      ),
    ),
  );

  final position = controller.position;
  position.lentPixels = lentPixels;

  final activity = BallisticNestedScrollActivity(
    position,
    FrictionSimulation(0.135, position.totalPixels, 600),
    tester,
    true,
  );

  position.beginActivity(activity);
  return _TestContext(position, activity);
}

/// Holds the scroll position and the activity whose simulation samples the test controls.
final class _TestContext {
  const _TestContext(this.position, this.activity);

  final NestedScrollPosition position;
  final BallisticNestedScrollActivity activity;
}
