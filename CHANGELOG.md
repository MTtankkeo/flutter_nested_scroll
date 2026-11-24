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
- Add horizontal scrolling support with `NestedScrollConnection.axis` and `NestedScrollControllerScope.scrollDirection`.

## 1.2.0
- Fix bouncing animations that fail to settle when floating-point residue remains in `lentPixels`.
- Move internal implementations to `lib/src`.
- Replace the deprecated Flutter Material import with Flutter widgets imports.
- Raise the minimum supported versions to Dart 3.13 and Flutter 3.47.
