## 1.0.0

- Initial release, extracted from `flutter_appbar` as a standalone package.
- Add regression tests for nested scrolling and controller lifecycle behavior.
- Fix overscroll calculations after pre-scroll consumption and preserve fling velocity without a connection.
- Fix accumulated consumption in child-first and ancestor-first propagation.
- Fix controller replacement and ownership updates when `NestedScrollControllerScope` rebuilds.

## 1.0.0+1

- Rename `NestedScrollConnectionPropagation` enum identifier to `NestedScrollPropagation`.

## 1.1.0

- Add `NestedScrollPosition.contentExtent` to report content length along the scroll axis without enabling `shrinkWrap`, including content shorter than the viewport.
