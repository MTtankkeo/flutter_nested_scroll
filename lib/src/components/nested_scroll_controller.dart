import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';

/// A [ScrollController] that always uses [NestedScrollPosition].
class NestedScrollController extends ScrollController {
  new({
    super.debugLabel,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.onAttach,
    super.onDetach,
  });

  @override
  NestedScrollPosition get position => super.position as NestedScrollPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return NestedScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}
