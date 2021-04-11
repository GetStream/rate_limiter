import 'debounce.dart';
import 'throttle.dart';

/// Useful rate limiter extensions for [Function] class.
extension RateLimit on Function {
  /// Converts this into a [Debounce] function.
  Debounce debounced(
    Duration wait, {
    bool leading = false,
    bool trailing = true,
    Duration? maxWait,
  }) =>
      Debounce(
        this,
        wait,
        leading: leading,
        trailing: trailing,
        maxWait: maxWait,
      );

  /// Converts this into a [Throttle] function.
  Throttle throttled(
    Duration wait, {
    bool leading = true,
    bool trailing = true,
  }) =>
      Throttle(
        this,
        wait,
        leading: leading,
        trailing: trailing,
      );
}

/// TopLevel lambda to create [Debounce] functions.
Debounce debounce(
  Function func,
  Duration wait, {
  bool leading = false,
  bool trailing = true,
  Duration? maxWait,
}) =>
    Debounce(
      func,
      wait,
      leading: leading,
      trailing: trailing,
      maxWait: maxWait,
    );

/// TopLevel lambda to create [Throttle] functions.
Throttle throttle(
  Function func,
  Duration wait, {
  bool leading = true,
  bool trailing = true,
}) =>
    Throttle(
      func,
      wait,
      leading: leading,
      trailing: trailing,
    );
