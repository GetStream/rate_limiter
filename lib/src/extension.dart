import 'dart:async';

import 'backoff.dart';
import 'buffer.dart';
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
///
/// Deliberately not [BufferFlushCallback], which returns `FutureOr<void>`: a
/// plain `void` function is a subtype of this, so both shapes resolve here.
extension BufferExtension<T> on void Function(List<T> items) {
  /// Converts this into a [Buffer] function.
  Buffer<T> buffered(
    Duration wait, {
    int? maxSize,
    int? maxQueueSize,
    OverflowPolicy overflow = OverflowPolicy.dropOldest,
    BufferErrorCallback<T>? onError,
    BufferDropCallback<T>? onDrop,
  }) =>
      Buffer(
        this,
        wait,
        maxSize: maxSize,
        maxQueueSize: maxQueueSize,
        overflow: overflow,
        onError: onError,
        onDrop: onDrop,
      );
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

/// TopLevel lambda to create [Buffer] functions.
Buffer<T> buffer<T>(
  BufferFlushCallback<T> onFlush,
  Duration wait, {
  int? maxSize,
  int? maxQueueSize,
  OverflowPolicy overflow = OverflowPolicy.dropOldest,
  BufferErrorCallback<T>? onError,
  BufferDropCallback<T>? onDrop,
}) =>
    Buffer(
      onFlush,
      wait,
      maxSize: maxSize,
      maxQueueSize: maxQueueSize,
      overflow: overflow,
      onError: onError,
      onDrop: onDrop,
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
