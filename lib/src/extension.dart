import 'dart:async';

import 'backoff.dart';
import 'debounce.dart';
import 'throttle.dart';

/// Useful rate limiter extensions for [Function] class.
extension BackOffExtension<T> on FutureOr<T> Function() {
  /// Converts this into a [BackOff] function.
  Future<T> backOff({
    Duration delayFactor = const Duration(milliseconds: 200),
    double randomizationFactor = 0.25,
    Duration maxDelay = const Duration(seconds: 30),
    int maxAttempts = 8,
    FutureOr<bool> Function(Object error, int attempt)? retry,
  }) =>
      BackOff(
        this,
        delayFactor: delayFactor,
        randomizationFactor: randomizationFactor,
        maxDelay: maxDelay,
        maxAttempts: maxAttempts,
        retryIf: retry,
      ).call();
}

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

/// TopLevel lambda to apply [BackOff] to functions.
Future<T> backOff<T>(
  FutureOr<T> Function() func, {
  Duration delayFactor = const Duration(milliseconds: 200),
  double randomizationFactor = 0.25,
  Duration maxDelay = const Duration(seconds: 30),
  int maxAttempts = 8,
  FutureOr<bool> Function(Object error, int attempt)? retryIf,
}) =>
    BackOff(
      func,
      delayFactor: delayFactor,
      randomizationFactor: randomizationFactor,
      maxDelay: maxDelay,
      maxAttempts: maxAttempts,
      retryIf: retryIf,
    ).call();

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
