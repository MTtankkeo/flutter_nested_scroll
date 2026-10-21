import 'package:flutter/widgets.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';

/// Signature for a function that creates a [NestedScrollController] when needed.
/// Called only if no controller exists in the current context.
typedef NestedScrollControllerBuilder =
    NestedScrollController Function(
      BuildContext context,
    );

/// Signature for building a widget that requires a [NestedScrollController].
typedef NestedScrollWidgetBuilder =
    Widget Function(
      BuildContext context,
      NestedScrollController controller,
    );

/// Ensures a single [NestedScrollController] is used within the widget tree.
///
/// If an ancestor has already provided a [NestedScrollController] via
/// [PrimaryScrollController], this widget uses that controller to avoid
/// conflicts caused by multiple controllers being created by different
/// widgets or packages.
///
/// Otherwise, it creates a new [NestedScrollController] for its children.
class NestedScrollControllerScope extends StatefulWidget {
  const NestedScrollControllerScope({
    super.key,
    required this.factory,
    required this.builder,
    this.controller,
  });

  /// Called to create a [NestedScrollController] if no controller is provided.
  /// Used only when the widget needs to generate a controller for its children.
  final NestedScrollControllerBuilder factory;

  /// Builds widgets with the available [NestedScrollController].
  final NestedScrollWidgetBuilder builder;

  /// Optional controller that can be passed from outside.
  /// If provided, the widget will use this instead of creating a new one.
  final NestedScrollController? controller;

  @override
  State<NestedScrollControllerScope> createState() => _NestedScrollControllerScopeState();
}

class _NestedScrollControllerScopeState extends State<NestedScrollControllerScope> {
  NestedScrollController? _controller;

  /// Only controllers created by this scope are owned by it.
  bool _ownsController = false;

  @override
  void didUpdateWidget(NestedScrollControllerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller?.dispose();
      _controller = null;
      _ownsController = false;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = PrimaryScrollController.maybeOf(context);

    // Reuse the existing NestedScrollController.
    if (primary != null && primary is NestedScrollController) {
      return widget.builder(context, primary);
    }

    // Create a NestedScrollController if none exists.
    if (_controller == null) {
      _controller = widget.controller ?? widget.factory(context);
      _ownsController = widget.controller == null;
    }

    return PrimaryScrollController(
      scrollDirection: .vertical,
      controller: _controller!,
      child: widget.builder(context, _controller!),
    );
  }
}
