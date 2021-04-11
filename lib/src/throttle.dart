import 'debounce.dart';

/// Creates a throttled function that only invokes `func` at most once per
/// every `wait` milliseconds. The throttled function comes with a [Throttle.cancel]
/// method to cancel delayed `func` invocations and a [Throttle.flush] method to
/// immediately invoke them. Provide `leading` and/or `trailing` to indicate
/// whether `func` should be invoked on the `leading` and/or `trailing` edge of the `wait` timeout.
/// The `func` is invoked with the last arguments provided to the
/// throttled function. Subsequent calls to the throttled function return the
/// result of the last `func` invocation.
///
/// **Note:** If `leading` and `trailing` options are `true`, `func` is
/// invoked on the trailing edge of the timeout only if the throttled function
/// is invoked more than once during the `wait` timeout.
///
/// If `wait` is [Duration.zero] and `leading` is `false`, `func` invocation is deferred
/// until the next tick.
///
/// See [David Corbacho's article](https://css-tricks.com/debouncing-throttling-explained-examples/)
/// for details over the differences between [Throttle] and [Debounce].
///
/// Some examples:
///
/// Avoid excessively rebuilding UI progress while uploading data to server.
/// ```dart
///   void updateUI(Data data) {
///     updateProgress(data);
///   }
///
///   final throttledUpdateUI = Throttle(
///     updateUI,
///     const Duration(milliseconds: 350),
///   );
///
///   void onUploadProgressChanged(progress) {
///      throttledUpdateUI(progress);
///   }
/// ```
///
/// Cancel the trailing throttled invocation.
/// ```dart
///   void dispose() {
///     throttled.cancel();
///   }
/// ```
///
/// Check for pending invocations.
/// ```dart
///   final status = throttled.isPending ? "Pending..." : "Ready";
/// ```
class Throttle {
  /// Creates a new instance of [Throttle]
  Throttle(
    Function func,
    Duration wait, {
    bool leading = true,
    bool trailing = true,
  }) : _debounce = Debounce(
          func,
          wait,
          leading: leading,
          trailing: trailing,
          maxWait: wait,
        );

  final Debounce _debounce;

  /// Cancels all the remaining delayed functions.
  void cancel() => _debounce.cancel();

  /// Immediately invokes all the remaining delayed functions.
  Object? flush() => _debounce.flush();

  /// True if there are functions remaining to get invoked.
  bool get isPending => _debounce.isPending;

  /// Calls/invokes this class like a function.
  /// Pass [args] and [namedArgs] to be used while invoking `func`.
  Object? call([List<Object>? args, Map<Symbol, Object>? namedArgs]) =>
      _debounce.call(args, namedArgs);
}
