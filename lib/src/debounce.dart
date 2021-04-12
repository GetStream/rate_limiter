import 'dart:async' show Timer;
import 'dart:math' as math;

const _undefined = Object();

/// Creates a debounced function that delays invoking `func` until after `wait`
/// milliseconds have elapsed since the last time the debounced function was
/// invoked. The debounced function comes with a [Debounce.cancel] method to cancel
/// delayed `func` invocations and a [Debounce.flush] method to immediately invoke them.
/// Provide `leading` and/or `trailing` to indicate whether `func` should be
/// invoked on the `leading` and/or `trailing` edge of the `wait` interval.
/// The `func` is invoked with the last arguments provided to the [call]
/// function. Subsequent calls to the debounced function return the result of
/// the last `func` invocation.
///
/// **Note:** If `leading` and `trailing` options are `true`, `func` is
/// invoked on the trailing edge of the timeout only if the debounced function
/// is invoked more than once during the `wait` timeout.
///
/// If `wait` is [Duration.zero] and `leading` is `false`,
/// `func` invocation is deferred until the next tick.
///
/// See [David Corbacho's article](https://css-tricks.com/debouncing-throttling-explained-examples/)
/// for details over the differences between [Debounce] and [Throttle].
///
/// Some examples:
///
/// Avoid calling costly network calls when user is typing something.
/// ```dart
///   void fetchData(String query) async {
///     final data = api.getData(query);
///     doSomethingWithTheData(data);
///   }
///
///   final debouncedFetchData = Debounce(
///     fetchData,
///     const Duration(milliseconds: 350),
///   );
///
///   void onSearchQueryChanged(query) {
///      debouncedFetchData([query]);
///   }
/// ```
///
/// Cancel the trailing debounced invocation.
/// ```dart
///   void dispose() {
///     debounced.cancel();
///   }
/// ```
///
/// Check for pending invocations.
/// ```dart
///   final status = debounced.isPending ? "Pending..." : "Ready";
/// ```
class Debounce {
  /// Creates a new instance of [Debounce].
  Debounce(
    this._func,
    Duration wait, {
    bool leading = false,
    bool trailing = true,
    Duration? maxWait,
  })  : _leading = leading,
        _trailing = trailing,
        _wait = wait.inMilliseconds,
        _maxing = maxWait != null {
    if (_maxing) {
      _maxWait = math.max(maxWait!.inMilliseconds, _wait);
    }
  }

  final Function _func;
  final bool _leading;
  final bool _trailing;
  final int _wait;
  final bool _maxing;

  int? _maxWait;
  Object? _lastArgs = _undefined;
  Object? _lastNamedArgs = _undefined;
  Timer? _timer;
  int? _lastCallTime;
  Object? _result;
  int _lastInvokeTime = 0;

  Object? _invokeFunc(int time) {
    final args = _lastArgs as List<Object>?;
    final namedArgs = _lastNamedArgs as Map<Symbol, Object>?;
    _lastInvokeTime = time;
    _lastArgs = _lastNamedArgs = _undefined;
    return _result = Function.apply(_func, args, namedArgs);
  }

  Timer _startTimer(Function pendingFunc, int wait) =>
      Timer(Duration(milliseconds: wait), () => pendingFunc());

  bool _shouldInvoke(int time) {
    // This is our first call.
    if (_lastCallTime == null) return true;

    final timeSinceLastCall = time - _lastCallTime!;
    final timeSinceLastInvoke = time - _lastInvokeTime;

    // Either activity has stopped and we're at the
    // trailing edge, the system time has gone backwards and we're treating
    // it as the trailing edge, or we've hit the `maxWait` limit.
    return (timeSinceLastCall >= _wait) ||
        (timeSinceLastCall < 0) ||
        (_maxing && timeSinceLastInvoke >= _maxWait!);
  }

  Object? _trailingEdge(int time) {
    _timer = null;

    // Only invoke if we have `_lastArgs` or `_lastNamedArgs` which means
    // `func` has been debounced at least once.
    if (_trailing &&
        (_lastArgs != _undefined || _lastNamedArgs != _undefined)) {
      return _invokeFunc(time);
    }
    _lastArgs = _lastNamedArgs = _undefined;
    return _result;
  }

  int _remainingWait(int time) {
    final timeSinceLastCall = time - _lastCallTime!;
    final timeSinceLastInvoke = time - _lastInvokeTime;
    final timeWaiting = _wait - timeSinceLastCall;

    return _maxing
        ? math.min(timeWaiting, _maxWait! - timeSinceLastInvoke)
        : timeWaiting;
  }

  void _timerExpired() {
    final time = DateTime.now().millisecondsSinceEpoch;
    if (_shouldInvoke(time)) {
      _trailingEdge(time);
    } else {
      // Restart the timer.
      _timer = _startTimer(_timerExpired, _remainingWait(time));
    }
  }

  Object? _leadingEdge(int time) {
    // Reset any `maxWait` timer.
    _lastInvokeTime = time;
    // Start the timer for the trailing edge.
    _timer = _startTimer(_timerExpired, _wait);
    // Invoke the leading edge.
    return _leading ? _invokeFunc(time) : _result;
  }

  /// Cancels all the remaining delayed functions.
  void cancel() {
    _timer?.cancel();
    _lastInvokeTime = 0;
    _lastCallTime = _timer = null;
    _lastArgs = _lastNamedArgs = _undefined;
  }

  /// Immediately invokes all the remaining delayed functions.
  Object? flush() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _timer == null ? _result : _trailingEdge(now);
  }

  /// True if there are functions remaining to get invoked.
  bool get isPending => _timer != null;

  /// Dynamically call this [Debounce] with the specified arguments.
  ///
  /// Acts the same as calling [_func] with positional arguments
  /// corresponding to the elements of [args] and
  /// named arguments corresponding to the elements of [namedArgs].
  ///
  /// This includes giving the same errors if [_func] isn't callable or
  /// if it expects different parameters.
  ///
  /// Example:
  /// ```dart
  /// List<Movie> fetchMovies(
  ///    String movieName, {
  ///    bool adult = false,
  ///  }) async {
  ///    final data = api.getData(query);
  ///    doSomethingWithTheData(data);
  ///  }
  ///
  /// final debouncedFetchMovies = Debounce(
  ///    fetchMovies,
  ///   const Duration(milliseconds: 350),
  /// );
  ///
  /// debouncedFetchMovies(['tenet'], {#adult: true});
  /// ```
  ///
  /// gives exactly the same result as
  /// ```
  /// fetchMovies('tenet', adult: true).
  /// ```
  Object? call([List<Object>? args, Map<Symbol, Object>? namedArgs]) {
    final time = DateTime.now().millisecondsSinceEpoch;
    final isInvoking = _shouldInvoke(time);

    _lastArgs = args;
    _lastNamedArgs = namedArgs;
    _lastCallTime = time;

    if (isInvoking) {
      if (_timer == null) {
        return _leadingEdge(_lastCallTime!);
      }
      if (_maxing) {
        // Handle invocations in a tight loop.
        _timer = _startTimer(_timerExpired, _wait);
        return _invokeFunc(_lastCallTime!);
      }
    }
    _timer ??= _startTimer(_timerExpired, _wait);
    return _result;
  }
}
