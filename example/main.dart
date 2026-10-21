import 'package:flutter/material.dart';
import 'package:flutter_nested_scroll/flutter_nested_scroll.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: NestedScrollExample(),
        ),
      ),
    ),
  );
}

/// N.B. Uses setState and height changes only to keep this example easy to follow.
/// This approach rebuilds the widget subtree and triggers layout as the header moves.
///
/// For performance-critical production use, a dedicated RenderBox implementation
/// is strongly recommended to avoid rebuilding the widget subtree on every update.
class NestedScrollExample extends StatefulWidget {
  const NestedScrollExample({super.key});

  @override
  State<NestedScrollExample> createState() => _NestedScrollExampleState();
}

class _NestedScrollExampleState extends State<NestedScrollExample> {
  /// The header height in logical pixels when fully expanded.
  static const _maxHeaderExtent = 160.0;

  /// The current header height, starting fully expanded and shrinking to zero.
  double _headerExtent = _maxHeaderExtent;

  /// Resizes the header using the available scroll offset from [position].
  /// Returns the signed amount consumed so the list can handle the remainder.
  double _consumeHeaderOffset(double available, NestedScrollPosition position) {
    // No consume when bouncing overscroll for appbar pixels safety.
    if (position.totalPixels < position.minScrollExtent || position.totalPixels > position.maxScrollExtent) {
      return 0;
    }

    // Positive offsets expand the header, negative offsets collapse it.
    final nextExtent = (_headerExtent + available).clamp(0.0, _maxHeaderExtent);
    final consumed = nextExtent - _headerExtent;

    // Rebuild only when the header height actually changes.
    if (consumed != 0) {
      setState(() => _headerExtent = nextExtent);
    }

    // Return the consumed amount, not the remainder.
    // The list handles the rest.
    return consumed;
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollControllerScope(
      factory: (_) => NestedScrollController(),
      builder: (context, controller) {
        return NestedScrollConnection(
          onPreScroll: _consumeHeaderOffset,
          child: Column(
            children: [
              SizedBox(
                height: _headerExtent,
                child: const ColoredBox(
                  color: Colors.redAccent,
                  child: Center(
                    child: Text(
                      'Header',
                      style: .new(fontSize: 24),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text('Item $index'),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
