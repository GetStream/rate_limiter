## [1.2.0] - (11-08-2026)

* Added `waitBuilder` to `Debounce` and `Throttle`, deriving the wait from the
  arguments a call was made with, so a single instance can vary its delay
  instead of needing one instance per delay.

## [1.1.0] - (11-08-2026)

* Read the current time through `package:clock` instead of `DateTime.now()`, so
  `Debounce` and `Throttle` can be tested deterministically with `fakeAsync`.
* Fixed `Debounce.flush()` and `Throttle.flush()` leaving their timer armed. The
  orphaned timer rescheduled itself, which made `isPending` report `true` again
  shortly after a flush.
* Raised the minimum Dart SDK to `^3.4.0`, as required by `package:clock`.

## [1.0.0] - (14-12-2022)

* Added BackOff.
* Added support for passing nullable values in Debounce and Throttle function.

## [0.1.1] - (13-04-2021)

* Add example.

## [0.1.0] - (13-04-2021)

* Initial release.