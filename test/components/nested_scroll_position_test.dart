import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setPixels', () {
    // Pre-scroll can consume none, half, or all of an 80-pixel movement in either direction.
    // The child should move only by the remainder and notify only when its position changes.
    // Full consumption should leave the child stationary and enable nested scrolling.
    for (final delta in [-80.0, 80.0]) {
      for (final fraction in [0.0, 0.5, 1.0]) {
        testWidgets('moves by the remainder of $delta after pre-scroll consumes $fraction', (tester) async {
          // Let the parent consume a share of the movement.
          final calls = <double>[];
          final context = await _pumpNestedScroll(
            tester,
            onPreScroll: (available, position) {
              calls.add(available);
              return available * fraction;
            },
          );

          final position = context.position;

          // Move in the selected direction.
          expect(position.setPixels(200 + delta), 0);

          // Only the remainder moves the child.
          expect(calls, [-delta]);
          expect(position.pixels, 200 + delta * (1 - fraction));
          expect(
            context.notifications.whereType<ScrollUpdateNotification>().length,
            fraction == 1 ? 0 : 1,
          );

          if (fraction == 1) {
            expect(position.isNestedScrolling, isTrue);
          }
        });
      }
    }

    // Repeating the current offset or adding a sub-tolerance delta should do nothing.
    // Neither request should change the position, call the parent, or emit scroll notifications.
    testWidgets('ignores unchanged and sub-tolerance offsets', (tester) async {
      // Track callbacks at the start boundary.
      var calls = 0;

      final context = await _pumpNestedScroll(
        tester,
        initialOffset: 0,
        onPreScroll: (_, _) {
          calls++;
          return 0;
        },
      );

      // Request zero and negligible movement.
      expect(context.position.setPixels(0), 0);
      expect(context.position.setPixels(precisionErrorTolerance / 2), 0);

      // Neither the position nor notifications change.
      expect(context.position.pixels, 0);
      expect(calls, 0);
      expect(context.notifications, isEmpty);
    });

    // A position should still scroll normally without a NestedScrollConnection ancestor.
    // Moving from 200 to 250 should notify listeners once and report a 50-pixel update.
    testWidgets('works without a connection and notifies the actual delta once', (tester) async {
      var changes = 0;

      // Observe a standalone scroll position.
      final context = await _pumpNestedScroll(tester, connected: false);

      context.position.addListener(() => changes++);

      // Move 50 pixels within the boundaries.
      expect(context.position.setPixels(250), 0);

      // Report the actual movement exactly once.
      expect(context.position.pixels, 250);
      expect(changes, 1);
      final update = context.notifications.whereType<ScrollUpdateNotification>().single;
      expect(update.scrollDelta, 50);
      expect(update.metrics.pixels, 250);
    });

    for (final atEnd in [false, true]) {
      // Request 40 pixels beyond either boundary and let post-scroll consume none, half, or all.
      // The child should stay at the boundary and report only the unconsumed overflow.
      // Full consumption should suppress overscroll notifications and enable nested scrolling.
      for (final fraction in [0.0, 0.5, 1.0]) {
        testWidgets('post-scroll consumes $fraction of overscroll at ${atEnd ? 'end' : 'start'}', (tester) async {
          // Let the parent consume a share of the overflow.
          final calls = <double>[];
          final context = await _pumpNestedScroll(
            tester,
            onPostScroll: (available, _) {
              calls.add(available);
              return available * fraction;
            },
          );

          final position = context.position;
          final boundary = atEnd ? position.maxScrollExtent : position.minScrollExtent;
          final excess = atEnd ? 40.0 : -40.0;

          // Move beyond the selected boundary.
          final remaining = position.setPixels(boundary + excess);

          // Clamp the child and report only unconsumed overflow.
          expect(calls, [-excess]);
          expect(position.pixels, boundary);
          expect(remaining, excess * (1 - fraction));
          final overscrolls = context.notifications.whereType<OverscrollNotification>();
          if (fraction == 1) {
            expect(overscrolls, isEmpty);
            expect(position.isNestedScrolling, isTrue);
          } else {
            expect(overscrolls.single.overscroll, remaining);
          }
        });
      }

      // Pre-scroll must reduce the overflow before clamping or bouncing handles the remainder.
      // Consuming 30 pixels leaves 10 pixels of overflow; consuming 60 leaves the child 20 pixels inside.
      // Check both boundaries and physics types, including that no post-scroll runs without overflow.
      for (final physics in [const ClampingScrollPhysics(), const BouncingScrollPhysics()]) {
        for (final consumed in [30.0, 60.0]) {
          testWidgets('pre-scroll consumes $consumed near ${atEnd ? 'end' : 'start'} with ${physics.runtimeType}', (
            tester,
          ) async {
            // Consume movement before the child reaches its boundary.
            final postScroll = <double>[];
            final context = await _pumpNestedScroll(
              tester,
              physics: physics,
              onPreScroll: (available, _) => available.sign * consumed,
              onPostScroll: (available, _) {
                postScroll.add(available);
                return 0;
              },
            );

            final position = context.position;
            final boundary = atEnd ? position.maxScrollExtent : 0.0;
            final excess = atEnd ? 40.0 : -40.0;

            // Request a movement that would otherwise overscroll.
            final remaining = position.setPixels(boundary + excess);

            // Pre-scroll reduces or eliminates the overflow.
            if (consumed < excess.abs()) {
              expect(remaining, physics is ClampingScrollPhysics ? excess.sign * 10 : 0);
              expect(position.totalPixels, boundary + (physics is BouncingScrollPhysics ? excess.sign * 10 : 0));
              expect(postScroll, [-excess.sign * 10]);
            } else {
              expect(remaining, 0);
              expect(position.pixels, boundary - excess.sign * 20);
              expect(postScroll, isEmpty);
            }
          });
        }
      }
    }

    // Raw position updates should bypass parent consumption even when callbacks would consume everything.
    // Normal boundary rules still apply: requesting -30 should stop at zero and return -30 as overflow.
    testWidgets('setRawPixels bypasses connection callbacks but respects boundaries', (tester) async {
      // Track callbacks that would consume all movement.
      var calls = 0;
      double consume(double available, NestedScrollPosition _) {
        calls++;
        return available;
      }

      final context = await _pumpNestedScroll(
        tester,
        onPreScroll: consume,
        onPostScroll: consume,
      );

      // Raw movement works inside the boundaries.
      expect(context.position.setRawPixels(240), 0);
      expect(context.position.pixels, 240);

      // Boundary clipping still applies without callbacks.
      expect(context.position.setRawPixels(-30), -30);
      expect(context.position.pixels, 0);
      expect(calls, 0);
    });
  });

  group('bouncing', () {
    // Split a 40-pixel bounce between parent and child at either boundary.
    // Parent consumption belongs in lentPixels; the remaining bounce belongs in pixels.
    // Their sum must preserve the requested offset, and isBouncing must reflect borrowed pixels.
    for (final atEnd in [false, true]) {
      for (final fraction in [0.0, 0.5, 1.0]) {
        testWidgets('splits bounce at ${atEnd ? 'end' : 'start'} with parent consuming $fraction', (tester) async {
          // Share the bounce between parent and child.
          final bounces = <double>[];
          final context = await _pumpNestedScroll(
            tester,
            physics: const BouncingScrollPhysics(),
            onBouncing: (available, _) {
              bounces.add(available);
              return available * fraction;
            },
          );

          final position = context.position;
          final boundary = atEnd ? position.maxScrollExtent : 0.0;
          final excess = atEnd ? 40.0 : -40.0;

          // Overscroll the selected boundary.
          expect(position.setPixels(boundary + excess), 0);

          // Borrowed and visible pixels preserve the total movement.
          expect(bounces, [excess]);
          expect(position.lentPixels, excess * fraction);
          expect(position.pixels, boundary + excess * (1 - fraction));
          expect(position.totalPixels, boundary + excess);
          expect(position.isBouncing, fraction != 0);
        });
      }
    }

    // Post-scroll gets a chance to consume overflow before the bouncing callback runs.
    // If it consumes all 40 pixels, the child should stay at zero with no borrowed pixels or bounce callback.
    testWidgets('post-scroll consumption prevents bouncing', (tester) async {
      // Consume all overflow during post-scroll.
      var bounceCalls = 0;

      final context = await _pumpNestedScroll(
        tester,
        physics: const BouncingScrollPhysics(),
        onPostScroll: (available, _) => available,
        onBouncing: (available, _) {
          bounceCalls++;
          return available;
        },
      );

      // Move past the start boundary.
      context.position.setPixels(-40);

      // No bounce remains for either parent or child.
      expect(context.position.pixels, 0);
      expect(context.position.lentPixels, 0);
      expect(bounceCalls, 0);
    });

    // Borrow 40 pixels beyond the start, then request an offset that brings totalPixels exactly to zero.
    // The parent should receive an equal repayment, clearing both lentPixels and the bounce state.
    testWidgets('repays borrowed pixels when returning exactly to the start', (tester) async {
      // Let the parent borrow the full bounce.
      final bounces = <double>[];
      final context = await _pumpNestedScroll(
        tester,
        physics: const BouncingScrollPhysics(),
        onBouncing: (available, _) {
          bounces.add(available);
          return available;
        },
      );
      final position = context.position;

      // Overscroll, then return the total offset to zero.
      position.setPixels(-40);
      position.setPixels(40);

      // Repayment clears the borrowed offset and bounce state.
      expect(bounces, [-40, 40]);
      expect(position.pixels, 0);
      expect(position.lentPixels, 0);
      expect(position.isBouncing, isFalse);
    });

    for (final fromEnd in [false, true]) {
      // Returning from either overscrolled boundary to offset 200 should clear the previous bounce.
      // The final position should be 200 with no borrowed pixels and no active bounce state.
      testWidgets('clears borrowed pixels when re-entering from ${fromEnd ? 'end' : 'start'}', (tester) async {
        // Let the parent handle bouncing at either boundary.
        final context = await _pumpNestedScroll(
          tester,
          physics: const BouncingScrollPhysics(),
          onBouncing: (available, _) => available,
        );

        final position = context.position;

        // Overscroll, then move back inside the content.
        position.setPixels(fromEnd ? position.maxScrollExtent + 40 : -40);
        position.setPixels(200);

        // The new position has no borrowed pixels.
        expect(position.pixels, 200);
        expect(position.lentPixels, 0);
        expect(position.isBouncing, isFalse);
      });

      // A large move can cross directly from one overscrolled boundary to the other.
      // Repay the original 40-pixel bounce before borrowing 80 pixels on the opposite side.
      // Check callback order and final offsets so the old bounce cannot leak into the new one.
      testWidgets('repays the old bounce before crossing from ${fromEnd ? 'end' : 'start'} to the opposite boundary', (
        tester,
      ) async {
        // Record borrowing and repayment in order.
        final bounces = <double>[];
        final context = await _pumpNestedScroll(
          tester,
          physics: const BouncingScrollPhysics(),
          onBouncing: (available, _) {
            bounces.add(available);
            return available;
          },
        );
        final position = context.position;
        final end = position.maxScrollExtent;

        // Cross directly from one overscrolled boundary to the other.
        position.setPixels(fromEnd ? end + 40 : -40);
        position.setPixels(fromEnd ? -80 : end + 80);

        // Repay the old bounce before borrowing on the other side.
        expect(bounces, fromEnd ? [40, -40, -80] : [-40, 40, 80]);
        expect(position.pixels, fromEnd ? 0 : end);
        expect(position.lentPixels, fromEnd ? -80 : 80);
      });
    }

    // Drag resistance must include the bounce held in lentPixels, even when the child stays at the boundary.
    // After borrowing 40 pixels, another 20-pixel drag should be reduced by the bouncing physics.
    // Check the resulting total offset and the reported user scroll direction.
    testWidgets('uses total pixels for drag resistance during a borrowed bounce', (tester) async {
      // Calculate resistance from an existing borrowed bounce.
      const physics = BouncingScrollPhysics();
      final context = await _pumpNestedScroll(
        tester,
        physics: physics,
        onBouncing: (available, _) => available,
      );

      final position = context.position;
      position.setPixels(-40);

      final before = position.totalPixels;
      final expectedDelta = physics.applyPhysicsToUserOffset(
        position.copyWith(pixels: before),
        20,
      );

      // Drag farther beyond the boundary.
      position.applyUserOffset(20);

      // Resistance uses the total offset, including borrowed pixels.
      expect(position.totalPixels, closeTo(before - expectedDelta, 1e-9));
      expect(expectedDelta, lessThan(20));
      expect(position.userScrollDirection, ScrollDirection.forward);
    });

    // Empty content has no scroll range, apart from the tiny extent used by bouncing physics.
    // Dragging and releasing it should settle near zero without exceptions or ongoing scrolling.
    for (final physics in [const ClampingScrollPhysics(), const BouncingScrollPhysics()]) {
      testWidgets('handles empty content with ${physics.runtimeType}', (tester) async {
        // Mount content with no scrollable extent.
        final context = await _pumpNestedScroll(
          tester,
          physics: physics,
          initialOffset: 0,
          contentHeight: 0,
        );

        final position = context.position;

        expect(position.maxScrollExtent, physics is BouncingScrollPhysics ? precisionErrorTolerance : 0);

        // Drag and release the empty scroll view.
        position.applyUserOffset(-20);
        position.goBallistic(0);
        await tester.pumpAndSettle();

        // Scrolling settles at the origin without exceptions.
        expect(position.totalPixels, closeTo(0, 0.01));
        expect(position.isScrollingNotifier.value, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ballistic scrolling', () {
    // Let the parent consume none, half, or all of a fling at velocity -600 or 600.
    // The child should start with the remaining velocity; full consumption should leave it idle.
    // Any resulting animation should finish within the scroll boundaries.
    for (final velocity in [-600.0, 600.0]) {
      for (final fraction in [0.0, 0.5, 1.0]) {
        testWidgets('fling consumes $fraction of velocity $velocity', (tester) async {
          // Let the parent consume a share of the fling velocity.
          final velocities = <double>[];
          final context = await _pumpNestedScroll(
            tester,
            onFling: (available, _) {
              velocities.add(available);
              return available * fraction;
            },
          );

          final position = context.position;
          velocities.clear();

          // Release with the selected velocity.
          position.goBallistic(velocity);

          // The child starts with only the remaining velocity.
          expect(velocities, [velocity]);
          expect(position.isBallisticScrolling, fraction != 1);
          expect(position.activity!.velocity, closeTo(velocity * (1 - fraction), 1e-6));

          // Finish the simulation and verify its resting position.
          await tester.pumpAndSettle();
          expect(position.isScrollingNotifier.value, isFalse);
          expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
        });
      }
    }

    // Without a parent connection, there is no consumer to take the fling velocity.
    // A positive fling should start a ballistic activity and move past the initial offset of 200.
    testWidgets('preserves fling velocity without a connection', (tester) async {
      // Mount a scroll view without a parent connection.
      final context = await _pumpNestedScroll(tester, connected: false);

      // Start a forward fling.
      context.position.goBallistic(600);

      // The fling starts and moves the child forward.
      expect(context.position.isBallisticScrolling, isTrue);
      await tester.pumpAndSettle();

      expect(context.position.pixels, greaterThan(200));
    });

    // A fully consumed drag enters nested mode, but releasing at zero velocity should end it.
    // The position should become idle and send exactly one NestedScrollEndNotification.
    // Its target and metrics must describe the position that just stopped.
    testWidgets('zero-velocity drag end clears nested mode and sends one end notification', (tester) async {
      // Enter nested mode by consuming the entire drag.
      final context = await _pumpNestedScroll(tester, onPreScroll: (available, _) => available);
      final position = context.position;
      position.applyUserOffset(-40);

      expect(position.isNestedScrolling, isTrue);

      // Release the drag without velocity.
      position.goBallistic(0);

      // Return to idle and report the correct final metrics once.
      expect(position.isNestedScrolling, isFalse);
      expect(position.activity, isA<IdleScrollActivity>());

      final end = context.notifications.whereType<NestedScrollEndNotification>().single;
      expect(end.target, same(position));
      expect(end.metrics.pixels, 200);
      expect(end.metrics.maxScrollExtent, position.maxScrollExtent);
    });

    // An idle position may still carry a nested-scrolling flag from an earlier interaction.
    // Starting a new fling should clear that flag while allowing ballistic scrolling to begin.
    testWidgets('starting from idle clears stale nested mode', (tester) async {
      // Leave a stale nested flag on an idle position.
      final context = await _pumpNestedScroll(tester);
      final position = context.position;
      position.goIdle();
      position.isNestedScrolling = true;

      // Start a new fling from idle.
      position.goBallistic(600);

      // The new fling uses normal scrolling mode.
      expect(position.isNestedScrolling, isFalse);
      expect(position.isBallisticScrolling, isTrue);
    });

    // Keep a fling moving through the parent while the child remains at the start boundary.
    // Another ballistic request should reuse the active nested simulation while consumption continues.
    // Once the parent stops consuming, nested mode should end and the child should settle at zero.
    testWidgets('retains nested ballistic activity until consumption stops', (tester) async {
      // Keep the child at the boundary by consuming all movement.
      var consume = true;
      final context = await _pumpNestedScroll(
        tester,
        initialOffset: 0,
        onPreScroll: (available, _) => consume ? available : 0,
      );
      final position = context.position;

      // Start a nested fling and verify that another request reuses it.
      position.applyUserOffset(40);
      position.goBallistic(-600);

      final activity = position.activity;
      expect(activity, isA<BallisticNestedScrollActivity>());

      position.goBallistic(-500);
      expect(position.activity, same(activity));

      // Advance time while the parent still consumes movement.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(position.pixels, 0);
      expect(position.isBallisticScrolling, isTrue);

      // Stop consumption and verify that the child settles at the boundary.
      consume = false;
      await tester.pumpAndSettle();
      expect(position.isNestedScrolling, isFalse);
      expect(position.pixels, 0);
      expect(position.isScrollingNotifier.value, isFalse);
    });

    // Remove the scroll view after advancing a fling by 16 milliseconds.
    // Processing the remaining scheduled frames should not raise exceptions after removal.
    testWidgets('can be removed during an active fling', (tester) async {
      // Advance a fling by one frame.
      final context = await _pumpNestedScroll(tester);
      context.position.goBallistic(600);
      await tester.pump(const Duration(milliseconds: 16));

      // Remove the scroll view before the fling finishes.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Pending animation work does not throw after removal.
      expect(tester.takeException(), isNull);
    });
  });

  // Exercise gesture handling with a forward drag followed by a fling in the opposite direction.
  // The drag should move the content, and the fling should finish within the scroll boundaries.
  // Scrolling must stop without exceptions after the gesture sequence completes.
  testWidgets('real drag and fling settle inside the scroll boundaries', (tester) async {
    // Let real gestures control an idle scroll view.
    final context = await _pumpNestedScroll(tester);
    context.position.goIdle();

    // Drag forward and verify that the content moves.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(context.position.pixels, greaterThan(200));

    // Fling in reverse and verify a safe resting position.
    await tester.fling(find.byType(SingleChildScrollView), const Offset(0, 200), 1500);
    await tester.pumpAndSettle();

    expect(context.position.pixels, inInclusiveRange(0, context.position.maxScrollExtent));
    expect(context.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('horizontal scrolling', () {
    for (final direction in TextDirection.values) {
      for (final reverse in [false, true]) {
        for (final physics in [const ClampingScrollPhysics(), const BouncingScrollPhysics()]) {
          testWidgets('$direction reverse $reverse $physics shares real horizontal drags and flings', (tester) async {
            final moves = <double>[];
            final flings = <double>[];
            final context = await _pumpNestedScroll(
              tester,
              axis: .horizontal,
              textDirection: direction,
              reverse: reverse,
              physics: physics,
              onPreScroll: (available, _) {
                moves.add(available);
                return available / 4;
              },
              onFling: (available, _) {
                flings.add(available);
                return available / 2;
              },
            );

            final position = context.position;
            position.goIdle();
            moves.clear();
            flings.clear();

            final drag = Offset(position.axisDirection == .right ? -80 : 80, 0);

            await tester.drag(find.byType(SingleChildScrollView), drag);
            await tester.pumpAndSettle();

            expect(position.axis, Axis.horizontal);
            expect(position.pixels, greaterThan(200));
            expect(moves.any((amount) => amount != 0), isTrue);

            await tester.fling(find.byType(SingleChildScrollView), -drag * 2.5, 1500);
            await tester.pumpAndSettle();

            expect(flings.any((velocity) => velocity != 0), isTrue);

            expect(
              position.pixels,
              inInclusiveRange(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );

            expect(position.isScrollingNotifier.value, isFalse);
            expect(tester.takeException(), isNull);
          });
        }

        testWidgets('$direction reverse $reverse shares and settles horizontal bouncing', (tester) async {
          final bounces = <double>[];
          final context = await _pumpNestedScroll(
            tester,
            axis: .horizontal,
            textDirection: direction,
            reverse: reverse,
            initialOffset: 0,
            physics: const BouncingScrollPhysics(),
            onBouncing: (available, position) {
              bounces.add(available);

              // Share outward movement, then repay the borrowed bounce on recovery.
              if (available * position.lentPixels < 0) {
                return available.sign * available.abs().clamp(0.0, position.lentPixels.abs());
              }

              return available / 2;
            },
          );
          final position = context.position;
          position.goIdle();

          final drag = Offset(position.axisDirection == .right ? 200 : -200, 0);

          await tester.drag(find.byType(SingleChildScrollView), drag);
          await tester.pumpAndSettle();

          expect(bounces.any((amount) => amount != 0), isTrue);

          expect(
            position.pixels,
            inInclusiveRange(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );

          expect(position.lentPixels, closeTo(0, precisionErrorTolerance));
          expect(position.isScrollingNotifier.value, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('contentExtent', () {
    testWidgets('reports short list content instead of the viewport height', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      await _pumpScrollView(
        tester,
        ListView(
          controller: controller,
          padding: .zero,
          children: const [
            SizedBox(height: 100),
            SizedBox(height: 100),
          ],
        ),
      );

      expect(controller.position.viewportDimension, 600);
      expect(controller.position.extentTotal, 600);
      expect(controller.position.contentExtent, 200);
    });

    testWidgets('includes padding and follows changes to the content', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      Future<void> pumpList(int count) => _pumpScrollView(
        tester,
        ListView.builder(
          controller: controller,
          padding: const EdgeInsets.only(top: 10, bottom: 20),
          itemExtent: 100,
          itemCount: count,
          itemBuilder: (_, _) => const SizedBox(),
        ),
      );

      await pumpList(2);
      expect(controller.position.contentExtent, 230);

      await pumpList(4);
      expect(controller.position.contentExtent, 430);

      await pumpList(0);
      expect(controller.position.contentExtent, 30);
    });

    testWidgets('reports an empty list as zero', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      await _pumpScrollView(
        tester,
        ListView(
          controller: controller,
          padding: .zero,
          children: const [],
        ),
      );

      expect(controller.position.contentExtent, 0);
    });

    testWidgets('measures a short grid including row spacing and padding', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      await _pumpScrollView(
        tester,
        GridView.builder(
          controller: controller,
          padding: const .only(top: 10, bottom: 20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 100,
            mainAxisSpacing: 12,
          ),
          itemCount: 3,
          itemBuilder: (_, _) => const SizedBox(),
        ),
      );

      expect(controller.position.contentExtent, 242);
    });

    testWidgets('adds only the direct slivers of a custom scroll view', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      await _pumpScrollView(
        tester,
        CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 10),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  const [
                    SizedBox(height: 50),
                    SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
          ],
        ),
      );

      expect(controller.position.contentExtent, 210);
    });

    testWidgets('supports horizontal reversed and shrink-wrapped lists', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      for (final shrinkWrap in [false, true]) {
        await _pumpScrollView(
          tester,
          ListView(
            controller: controller,
            padding: .zero,
            scrollDirection: .horizontal,
            reverse: true,
            shrinkWrap: shrinkWrap,
            children: const [
              SizedBox(width: 100),
              SizedBox(width: 100),
            ],
          ),
        );

        expect(controller.position.contentExtent, 200);
      }
    });

    testWidgets('reading a long list does not eagerly build its items', (tester) async {
      final controller = NestedScrollController();
      _disposeAfterTest(tester, controller);

      var builds = 0;
      await _pumpScrollView(
        tester,
        ListView.builder(
          controller: controller,
          padding: EdgeInsets.zero,
          itemExtent: 100,
          itemCount: 1000,
          itemBuilder: (_, _) {
            builds++;
            return const SizedBox();
          },
        ),
      );

      final buildsAfterLayout = builds;

      expect(controller.position.contentExtent, 100000);
      expect(builds, buildsAfterLayout);
      expect(builds, lessThan(20));
    });

    testWidgets('supports single-child content and stops before nested viewports', (tester) async {
      final outer = NestedScrollController();
      final inner = NestedScrollController();
      _disposeAfterTest(tester, outer);
      _disposeAfterTest(tester, inner);

      await _pumpScrollView(
        tester,
        SingleChildScrollView(
          controller: outer,
          child: SizedBox(
            height: 200,
            child: ListView(
              controller: inner,
              padding: EdgeInsets.zero,
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      );

      expect(outer.position.contentExtent, 200);
      expect(inner.position.contentExtent, 1000);

      final position = outer.position;

      await tester.pumpWidget(const SizedBox.shrink());
      expect(position.contentExtent, isNull);
    });
  });
}

/// A fixed viewport keeps offsets independent of the test window size.
/// Start a real drag activity so direct position updates also emit notifications.
Future<_TestContext> _pumpNestedScroll(
  WidgetTester tester, {
  ScrollPhysics physics = const ClampingScrollPhysics(),
  double initialOffset = 200,
  double contentHeight = 1000,
  Axis axis = .vertical,
  bool reverse = false,
  TextDirection textDirection = .ltr,
  bool connected = true,
  NestedScrollListener? onPreScroll,
  NestedScrollListener? onPostScroll,
  NestedScrollListener? onFling,
  NestedScrollListener? onBouncing,
}) async {
  // Create the controller and clean it up after unmounting the view.
  final controller = NestedScrollController(initialScrollOffset: initialOffset);
  final notifications = <ScrollNotification>[];

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  // Build the scroll view with an optional parent connection.
  Widget child = SingleChildScrollView(
    controller: controller,
    scrollDirection: axis,
    reverse: reverse,
    physics: physics,
    child: SizedBox(
      height: axis == Axis.vertical ? contentHeight : 400,
      width: axis == Axis.horizontal ? contentHeight : 300,
    ),
  );

  if (connected) {
    child = NestedScrollConnection(
      axis: axis,
      onPreScroll: onPreScroll,
      onPostScroll: onPostScroll,
      onFling: onFling,
      onBouncing: onBouncing,
      child: child,
    );
  }

  // Mount a fixed viewport and collect scroll notifications.
  await tester.pumpWidget(
    Directionality(
      textDirection: textDirection,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              notifications.add(notification);
              return false;
            },
            child: child,
          ),
        ),
      ),
    ),
  );

  {
    final details = DragUpdateDetails(
      globalPosition: .zero,
      primaryDelta: 0,
    );

    // Prime drag updates, then discard setup notifications.
    controller.position.drag(DragStartDetails(), () {}).update(details);
  }

  notifications.clear();

  return _TestContext(controller.position, notifications);
}

/// Provides the mounted scroll position and its captured notifications for assertions.
final class _TestContext {
  const _TestContext(this.position, this.notifications);

  /// The position to drive and inspect during the test.
  final NestedScrollPosition position;

  /// Scroll notifications collected after setup, in dispatch order.
  final List<ScrollNotification> notifications;
}

/// Mounts the scroll view in a fixed viewport to verify its content extent.
Future<void> _pumpScrollView(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 600,
          child: child,
        ),
      ),
    ),
  );
}

/// Unmounts the scroll views before disposing their controllers after each test.
void _disposeAfterTest(
  WidgetTester tester,
  NestedScrollController controller,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
