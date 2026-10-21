import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NestedScrollConnection', () {
    // Each event should visit three connections in propagation order and pass only the remainder.
    // Consuming 30, 20, and 10 pixels must return 60 in total, with the input sign preserved.
    // Check all four event types so their callbacks cannot accidentally be wired together.
    for (final event in _Event.values) {
      for (final propagation in NestedScrollConnectionPropagation.values) {
        for (final available in [-100.0, 100.0]) {
          testWidgets('${event.name}: ${propagation.name} preserves order and totals for $available', (tester) async {
            final calls = <(int, double)>[];
            final context = await _pumpConnections(
              tester,
              event: event,
              propagation: propagation,
              onConsume: (index, amount, position) {
                calls.add((index, amount));
                return amount.sign * [30, 20, 10][index];
              },
            );

            final consumed = event.dispatch(context.connection, available, context.position);
            final sign = available.sign;

            final childFirst = switch (propagation) {
              .selfFirst => true,
              .deferToAncestor => false,
              .directional => available > 0,
            };

            expect(
              calls,
              childFirst
                  ? [(0, available), (1, sign * 70), (2, sign * 50)]
                  : [(2, available), (1, sign * 90), (0, sign * 70)],
            );
            expect(consumed, sign * 60);
          });
        }
      }
    }

    // Once a connection consumes the entire input, later connections must not run.
    // The same early-stop rule applies to offsets, fling velocity, and bouncing.
    for (final event in _Event.values) {
      for (final propagation in NestedScrollConnectionPropagation.values) {
        testWidgets('${event.name}: ${propagation.name} stops after full consumption', (tester) async {
          final calls = <int>[];
          final context = await _pumpConnections(
            tester,
            event: event,
            propagation: propagation,
            onConsume: (index, available, _) {
              calls.add(index);
              return available;
            },
          );

          expect(event.dispatch(context.connection, 100, context.position), 100);
          expect(calls, [propagation == .deferToAncestor ? 2 : 0]);
        });
      }
    }

    // A matching ancestor predicate can take over before normal propagation starts.
    // Full consumption should prevent all other consumers from receiving the event.
    for (final event in _Event.values) {
      testWidgets('${event.name}: predicate takeover runs before the child', (tester) async {
        final calls = <int>[];
        final context = await _pumpConnections(
          tester,
          event: event,
          propagation: .selfFirst,
          predicate: (index, available, _) => index == 1 && available > 0,
          onConsume: (index, available, _) {
            calls.add(index);
            return available;
          },
        );

        expect(event.dispatch(context.connection, 100, context.position), 100);
        expect(calls, [1]);

        // A rejected predicate leaves the normal child-first order intact.
        calls.clear();
        expect(event.dispatch(context.connection, -100, context.position), -100);
        expect(calls, [0]);
      });
    }

    // Directional propagation orders mixed modes by priority, then reverses that order for negative input.
    // Each callback must still receive the remainder left by the previous callback.
    for (final available in [-100.0, 100.0]) {
      testWidgets('directional propagation orders mixed modes for $available', (tester) async {
        final calls = <(int, double)>[];
        final context = await _pumpConnections(
          tester,
          modes: const [
            .directional,
            .deferToAncestor,
            .selfFirst,
          ],
          onConsume: (index, amount, _) {
            calls.add((index, amount));
            return amount.sign * 10;
          },
        );

        expect(context.connection.preScroll(available, context.position), available.sign * 30);
        expect(calls, available > 0 ? [(2, 100.0), (0, 90.0), (1, 80.0)] : [(1, -100.0), (0, -90.0), (2, -80.0)]);
      });
    }

    // Missing callbacks should contribute zero without blocking callbacks on other connections.
    // A different event type must not invoke the callback registered for pre-scroll.
    testWidgets('skips absent callbacks and keeps event types separate', (tester) async {
      final calls = <int>[];
      final context = await _pumpConnections(
        tester,
        event: .preScroll,
        callbackIndices: {2},
        onConsume: (index, _, _) {
          calls.add(index);
          return 25;
        },
      );

      expect(context.connection.preScroll(100, context.position), 25);
      expect(calls, [2]);
      calls.clear();

      for (final event in [_Event.postScroll, _Event.fling, _Event.bouncing]) {
        expect(event.dispatch(context.connection, 100, context.position), 0);
      }

      expect(calls, isEmpty);
    });

    // Lookup should select the nearest connection even with unrelated widgets between ancestors.
    // The ancestor list should contain each connection once, from the child toward the root.
    testWidgets('finds the nearest connection and lists its ancestors', (tester) async {
      final context = await _pumpConnections(tester, onConsume: (_, _, _) => 0);
      final scrollContext = tester.element(find.byType(SingleChildScrollView));

      expect(NestedScrollConnection.of(scrollContext), same(context.connection));
      expect(context.connection.findSelfAndAncestorWidgets().map((widget) => widget.key), [
        const ValueKey(0),
        const ValueKey(1),
        const ValueKey(2),
      ]);
      expect(NestedScrollConnection.of(tester.element(find.byType(Directionality))), isNull);
    });
  });
}

/// Selects both the callback to install and the public event method to exercise.
enum _Event {
  preScroll,
  postScroll,
  fling,
  bouncing;

  double dispatch(
    NestedScrollConnectionState connection,
    double available,
    NestedScrollPosition position,
  ) {
    return switch (this) {
      .preScroll => connection.preScroll(available, position),
      .postScroll => connection.postScroll(available, position),
      .fling => connection.fling(available, position),
      .bouncing => connection.bouncing(available, position),
    };
  }
}

/// Builds three nested connections around a real scroll position; index zero is the innermost.
Future<_TestContext> _pumpConnections(
  WidgetTester tester, {
  _Event event = .preScroll,
  NestedScrollConnectionPropagation propagation = .directional,
  List<NestedScrollConnectionPropagation>? modes,
  Set<int> callbackIndices = const {0, 1, 2},
  bool Function(int index, double available, NestedScrollPosition position)? predicate,
  required double Function(int index, double available, NestedScrollPosition position) onConsume,
}) async {
  final controller = NestedScrollController();

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  // Ignore the initial ballistic request during layout; tests dispatch events after mounting.
  var ready = false;

  Widget child = SingleChildScrollView(
    controller: controller,
    child: const SizedBox(height: 1000),
  );

  for (var index = 0; index < 3; index++) {
    final connectionIndex = index;

    double consume(double available, NestedScrollPosition position) {
      expect(position, same(controller.position));
      return ready ? onConsume(connectionIndex, available, position) : 0;
    }

    final callback = callbackIndices.contains(index) ? consume : null;

    child = NestedScrollConnection(
      key: ValueKey(index),
      propagation: modes?[index] ?? propagation,
      predicate: predicate == null
          ? null
          : (available, position) => ready && predicate(connectionIndex, available, position),
      onPreScroll: event == .preScroll ? callback : null,
      onPostScroll: event == .postScroll ? callback : null,
      onFling: event == .fling ? callback : null,
      onBouncing: event == .bouncing ? callback : null,
      child: Padding(padding: EdgeInsets.zero, child: child),
    );
  }

  await tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Center(child: SizedBox(width: 300, height: 400, child: child)),
    ),
  );

  ready = true;

  return _TestContext(
    tester.state<NestedScrollConnectionState>(find.byKey(const ValueKey(0))),
    controller.position,
  );
}

/// Exposes the innermost connection and the position passed to its event callbacks.
final class _TestContext {
  const _TestContext(this.connection, this.position);

  final NestedScrollConnectionState connection;
  final NestedScrollPosition position;
}
