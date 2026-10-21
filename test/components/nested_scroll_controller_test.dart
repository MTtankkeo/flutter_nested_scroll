import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NestedScrollController', () {
    // Changing the physics type makes Flutter replace the scroll position.
    // Passing oldPosition through the controller should preserve the current offset instead of resetting it.
    testWidgets('preserves the offset when physics replaces the position', (tester) async {
      final controller = NestedScrollController(initialScrollOffset: 120);
      _disposeAfterTest(tester, controller);

      await _pumpNestedScroll(tester, controller: controller);
      controller.jumpTo(300);

      await tester.pumpAndSettle();
      final oldPosition = controller.position;

      // Rebuild the same scrollable with a different physics type.
      await _pumpNestedScroll(tester, controller: controller, physics: const BouncingScrollPhysics());

      expect(controller.position, isNot(same(oldPosition)));
      expect(controller.position.physics, isA<BouncingScrollPhysics>());
      expect(controller.offset, 300);
    });
  });
}

/// Rebuilds the same scroll view with the requested physics.
Future<void> _pumpNestedScroll(
  WidgetTester tester, {
  required NestedScrollController controller,
  ScrollPhysics physics = const ClampingScrollPhysics(),
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: SingleChildScrollView(
            controller: controller,
            physics: physics,
            child: const SizedBox(height: 1000),
          ),
        ),
      ),
    ),
  );
}

/// Detaches the scroll view before disposing its externally owned controller.
void _disposeAfterTest(WidgetTester tester, NestedScrollController controller) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
