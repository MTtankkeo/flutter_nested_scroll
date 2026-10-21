import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NestedScrollControllerScope', () {
    for (final axis in Axis.values) {
      testWidgets('provides primary inheritance for $axis scrolling', (tester) async {
        final owned = _TrackedController();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: NestedScrollControllerScope(
              scrollDirection: axis,
              factory: (_) => owned,
              builder: (context, selected) {
                return SingleChildScrollView(
                  primary: true,
                  scrollDirection: axis,
                  child: const SizedBox(
                    width: 1000,
                    height: 1000,
                  ),
                );
              },
            ),
          ),
        );

        expect(owned.position.axis, axis);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(owned.disposals, 1);
      });

      for (final sameAxis in [false, true]) {
        testWidgets('$axis nested scopes share controllers only on matching axes: $sameAxis', (tester) async {
          final outer = _TrackedController();
          final inner = _TrackedController();

          final Axis innerAxis = sameAxis ? axis : (axis == .vertical ? .horizontal : .vertical);

          await tester.pumpWidget(
            Directionality(
              textDirection: .ltr,
              child: Center(
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: NestedScrollControllerScope(
                    scrollDirection: axis,
                    factory: (_) => outer,
                    builder: (_, first) {
                      return NestedScrollControllerScope(
                        scrollDirection: innerAxis,
                        factory: (_) => inner,
                        builder: (_, second) {
                          expect(second, same(sameAxis ? first : inner));

                          return SingleChildScrollView(
                            primary: true,
                            scrollDirection: innerAxis,
                            child: const SizedBox(
                              width: 1000,
                              height: 1000,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );

          expect((sameAxis ? outer : inner).position.axis, innerAxis);
          expect(outer.hasClients, sameAxis);

          await tester.pumpWidget(const SizedBox.shrink());
          expect(outer.disposals, 1);
          expect(inner.disposals, sameAxis ? 0 : 1);

          if (sameAxis) inner.dispose();
        });
      }
    }

    // Without a suitable ancestor or explicit controller, the scope creates its own controller.
    // Rebuilding should reuse it, expose it to descendants, and dispose it once when removed.
    testWidgets('creates, provides, reuses, and disposes its own controller', (tester) async {
      final owned = _TrackedController();
      var creations = 0;

      for (var rebuild = 0; rebuild < 2; rebuild++) {
        await _pumpScope(
          tester,
          factory: (_) {
            creations++;
            return owned;
          },
          onController: (controller) => expect(controller, same(owned)),
        );
      }

      expect(creations, 1);
      expect(owned.disposals, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.disposals, 1);
    });

    // An explicit controller should bypass the factory and be provided to descendants.
    // Removing the scope must leave that externally owned controller usable.
    testWidgets('uses an explicit controller without disposing it', (tester) async {
      final external = _TrackedController();
      addTearDown(external.dispose);

      await _pumpScope(
        tester,
        controller: external,
        factory: (_) => throw StateError('The factory should not run.'),
        onController: (controller) => expect(controller, same(external)),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(external.disposals, 0);
      external.addListener(() {});
    });

    // A nested primary controller takes precedence over both an explicit controller and the factory.
    // The scope borrows the ancestor and must not dispose either externally supplied controller.
    for (final explicit in [false, true]) {
      testWidgets('prefers the nested ancestor with explicit controller $explicit', (tester) async {
        final ancestor = _TrackedController();
        final external = _TrackedController();
        addTearDown(ancestor.dispose);
        addTearDown(external.dispose);

        await _pumpScope(
          tester,
          primary: ancestor,
          controller: explicit ? external : null,
          factory: (_) => throw StateError('The factory should not run.'),
          onController: (controller) => expect(controller, same(ancestor)),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        expect(ancestor.disposals, 0);
        expect(external.disposals, 0);
      });
    }

    // An ordinary ScrollController cannot supply NestedScrollPosition instances.
    // The scope should provide its own nested controller while leaving the ancestor untouched.
    testWidgets('creates a nested controller under an ordinary primary controller', (tester) async {
      final ancestor = ScrollController();
      final owned = _TrackedController();
      addTearDown(ancestor.dispose);

      await _pumpScope(
        tester,
        primary: ancestor,
        factory: (_) => owned,
        onController: (controller) => expect(controller, same(owned)),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.disposals, 1);
      ancestor.addListener(() {});
    });

    // Nested scopes should share the controller provided by the outer scope instead of creating competing instances.
    // Removing both scopes should dispose the shared controller only through its owning scope.
    testWidgets('nested scopes share one controller and dispose it once', (tester) async {
      final owned = _TrackedController();
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: NestedScrollControllerScope(
            factory: (_) => owned,
            builder: (_, outer) => NestedScrollControllerScope(
              factory: (_) => throw StateError('The inner factory should not run.'),
              builder: (_, inner) {
                expect(inner, same(outer));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.disposals, 1);
    });

    // Replacing an inherited primary controller should update the controller passed to the builder.
    // This rebuild must not create a local controller or take ownership of either ancestor.
    testWidgets('follows changes to the inherited primary controller', (tester) async {
      final first = _TrackedController();
      final second = _TrackedController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      for (final ancestor in [first, second]) {
        await _pumpScope(
          tester,
          primary: ancestor,
          factory: (_) => throw StateError('The factory should not run.'),
          onController: (controller) => expect(controller, same(ancestor)),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(first.disposals, 0);
      expect(second.disposals, 0);
    });

    // A new explicit controller must replace the previous one when the same scope rebuilds.
    // Both controllers remain owned by the caller, including after the scope is removed.
    testWidgets('uses a replacement explicit controller', (tester) async {
      final first = _TrackedController();
      final second = _TrackedController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      for (final external in [first, second]) {
        await _pumpScope(
          tester,
          controller: external,
          factory: (_) => throw StateError('The factory should not run.'),
          onController: (controller) => expect(controller, same(external)),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(first.disposals, 0);
      expect(second.disposals, 0);
    });

    // Switching between generated and explicit controllers also changes disposal responsibility.
    // Release the old generated instance, preserve the external one, and create a fresh instance when needed.
    testWidgets('updates ownership when an explicit controller is added and removed', (tester) async {
      final generated = <_TrackedController>[];
      final external = _TrackedController();
      addTearDown(external.dispose);

      NestedScrollController create(BuildContext _) {
        final controller = _TrackedController();
        generated.add(controller);
        return controller;
      }

      await _pumpScope(tester, factory: create);
      expect(generated, hasLength(1));

      await _pumpScope(
        tester,
        controller: external,
        factory: create,
        onController: (controller) => expect(controller, same(external)),
      );
      expect(generated.first.disposals, 1);

      await _pumpScope(tester, factory: create, onController: (controller) => expect(controller, same(generated.last)));
      expect(generated, hasLength(2));
      expect(external.disposals, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(generated.map((controller) => controller.disposals), [1, 1]);
    });
  });
}

/// Keeps the scope at the same tree location while changing its inputs between pumps.
/// A descendant checks that the controller passed to the builder is also available through PrimaryScrollController.
Future<void> _pumpScope(
  WidgetTester tester, {
  NestedScrollController? controller,
  ScrollController? primary,
  required NestedScrollControllerBuilder factory,
  ValueChanged<NestedScrollController>? onController,
}) {
  final child = NestedScrollControllerScope(
    controller: controller,
    factory: factory,
    builder: (_, selected) {
      onController?.call(selected);
      return Builder(
        builder: (context) {
          expect(PrimaryScrollController.of(context), same(selected));

          return SingleChildScrollView(
            controller: selected,
            child: const SizedBox(height: 1000),
          );
        },
      );
    },
  );

  return tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: primary == null
          ? PrimaryScrollController.none(child: child)
          : PrimaryScrollController(controller: primary, child: child),
    ),
  );
}

/// Counts disposal calls to distinguish owned controllers from borrowed controllers.
final class _TrackedController extends NestedScrollController {
  int disposals = 0;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}
