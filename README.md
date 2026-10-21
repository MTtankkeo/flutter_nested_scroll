# Introduction

This package coordinates scroll events between a scrollable widget and its ancestors. It allows surrounding widgets to consume scroll offsets, fling velocity, and bouncing to implement custom scroll behavior.

---

Flutter's standard APIs can make Android- and iOS-style scroll coordination difficult. Similar to [Jetpack Compose nested scrolling](https://developer.android.com/develop/ui/compose/touch-input/scroll/nested-scroll-modifiers), this package lets ancestors consume movement before the child or handle the remainder afterward. It also coordinates fling velocity and bouncing without requiring a sliver-based layout.

For pull-to-refresh, notification-based implementations react after content moves. Consumption callbacks let the indicator handle movement first and pass the remainder to the content, keeping both in one continuous interaction.

Both vertical and horizontal scrolling are supported. Connections handle vertical events by default, set `axis: Axis.horizontal` to handle horizontal events.

## Related Packages

| Name | Introduction |
| --- | --- |
| [flutter_appbar](https://pub.dev/packages/flutter_appbar) | Flexible appbar behavior for scrollable content. |
| [flutter_refresh_indicator](https://pub.dev/packages/flutter_refresh_indicator) | A flexible, native-like refresh indicator built on flutter_appbar. |
| [flutter_infinite_scroll_pagination ](https://pub.dev/packages/flutter_infinite_scroll_pagination) | Easy infinite scroll loading with one-line wrapping, no setup needed. |
| [flutter_scroll_bottom_sheet](https://pub.dev/packages/flutter_scroll_bottom_sheet) | A bottom sheet widget that syncs smoothly with scroll events for a seamless UX. |

## Usage

### How to connect a scrollable widget?

Wrap your scrollable widget with `NestedScrollConnection` and assign a `NestedScrollController` to it. The connection receives events from the `NestedScrollPosition` managed by that controller.

See [example/main.dart](example/main.dart) for a commented example where a header consumes movement before the list.

> [!Note]
> Wrapping a standard `ScrollController` with a connection is not enough. The scrollable must use a `NestedScrollController` to participate in nested scrolling.

### How to use horizontal scrolling?

Set the connection's axis and the scrollable's direction to `Axis.horizontal`. When using `NestedScrollControllerScope`, set its `scrollDirection` to match:

```dart
NestedScrollConnection(
  axis: Axis.horizontal,
  onPreScroll: (available, position) {
    // Return the amount consumed by your component.
    return 0;
  },
  child: NestedScrollControllerScope(
    scrollDirection: Axis.horizontal,
    factory: (_) => NestedScrollController(),
    builder: (context, controller) => ListView.builder(
      controller: controller,
      scrollDirection: Axis.horizontal,
      itemCount: 20,
      itemBuilder: (context, index) => SizedBox(
        width: 120,
        child: Text('Item $index'),
      ),
    ),
  ),
);
```

Connections and predicates only receive events from their configured axis. Events pass through connections on the other axis to matching ancestors. Controller scopes share a primary controller only when their axes match.

With `reverse` or RTL text direction, callbacks still use scroll-coordinate signs rather than physical left/right directions.

### How much should a callback return?

Each event callback receives the available amount and the originating `NestedScrollPosition`. Return the amount your component consumed, keeping the same sign as the input.

For example, given `available == -80`, returning `-30` consumes 30 pixels and leaves `-50` for further processing. Return `0` to consume nothing, or `available` to consume everything. Do not return the remainder or consume more than the available amount.

| Callback | When it runs |
| --- | --- |
| onPreScroll | Before the child applies movement. Consume offsets here to let an ancestor handle part or all of the movement first. |
| onPostScroll | When movement remains after the child reaches its scroll boundary. |
| onFling | Before a ballistic simulation starts. Return the consumed velocity, in logical pixels per second. |
| onBouncing | When handling bouncing overflow or repaying a previously borrowed bounce offset. |

For pre-scroll and post-scroll offsets, positive values move toward the minimum scroll extent and negative values move toward the maximum. Fling velocity and bouncing use their respective event signs; preserve the sign supplied to each callback.

### How to control event propagation?

Connections can be nested. Set `propagation` to control which connection handles an event first. Each consumer receives the remaining amount, and propagation stops when the input is fully consumed.

| NestedScrollPropagation | Description |
| --- | --- |
| .selfFirst | Handle the event locally, then pass the remainder to ancestors. |
| .deferToAncestor | Let ancestors consume first, then handle the remainder locally. |
| .directional | The default. With directional connections, positive input visits the nearest connection first; negative input visits the outermost first. |

When directional propagation encounters mixed modes, it orders connections as `selfFirst`, `directional`, then `deferToAncestor` for positive input, and reverses that order for negative input.

Use `predicate` when a connection needs priority over the normal propagation order. Returning `true` gives that connection an early opportunity to consume the event. The predicate itself does not consume anything; its corresponding event callback must return the consumed amount.

### How to share a scroll controller?

`NestedScrollControllerScope` provides a controller to its builder and descendants through `PrimaryScrollController`. It selects a controller in the following order:

1. The primary controller provided by an ancestor, if it is a `NestedScrollController` with the same `scrollDirection`.
2. The explicit `controller` passed to the scope.
3. A controller created by `factory`.

The scope reuses its local controller across rebuilds and disposes controllers it creates. Controllers supplied explicitly or inherited from an ancestor remain owned by their caller.

Pass the controller received by the builder directly to your scrollable, as shown in the example. This also avoids depending on platform-specific primary controller inheritance.

### How to observe the end of scrolling?

Place a `NotificationListener<NestedScrollEndNotification>` above the scrollable. Its callback receives the `target` position that stopped scrolling and a snapshot of its scroll `metrics`.

Return `false` from the notification callback to allow the notification to continue to ancestors. Return `true` when you want to stop that notification from propagating.

## Scroll Position

`NestedScrollController.position` exposes a `NestedScrollPosition` for inspecting nested scroll state.

| Property | Description |
| --- | --- |
| pixels | The scroll offset of the child. |
| lentPixels | The bounce offset currently consumed by an ancestor. |
| totalPixels | The combined offset: `pixels + lentPixels`. |
| isBouncing | Whether a borrowed bounce offset remains, within the precision tolerance. |
| isBallisticScrolling | Whether the current activity is a ballistic scroll activity. |
| isNestedScrolling | Whether nested scrolling is active, allowing ballistic motion beyond the scroll boundaries of the child. |

The controller uses `BallisticNestedScrollActivity` to apply simulation deltas while ancestors consume movement. Most integrations only need the connection callbacks and do not need to create an activity directly.
