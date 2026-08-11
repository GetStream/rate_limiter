## [2.0.0]

* **BREAKING** Bumped the minimum Dart SDK to `^3.4.0`, as required by
  `package:clock`.
* Read the current time through `package:clock` instead of `DateTime.now()`, so
  `Debounce` and `Throttle` can be tested deterministically with `fakeAsync`.

## [1.0.0] - (14-12-2022)

* Added BackOff.
* Added support for passing nullable values in Debounce and Throttle function.

## [0.1.1] - (13-04-2021)

* Add example.

## [0.1.0] - (13-04-2021)

* Initial release.