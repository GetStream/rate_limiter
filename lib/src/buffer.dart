import 'dart:async';

/// Invoked with every item a [Buffer] collected, in the order they arrived.
typedef BufferFlushCallback<T> = FutureOr<void> Function(List<T> items);

/// Invoked when a flush a [Buffer] started itself fails, with the items that
/// flush was carrying so they can be re-queued rather than lost.
typedef BufferErrorCallback<T> = void Function(
  Object error,
  StackTrace stackTrace,
  List<T> items,
);

/// Invoked with the items a [Buffer] dropped to stay within `maxQueueSize`.
typedef BufferDropCallback<T> = void Function(List<T> items);

/// What a [Buffer] gives up when it is holding `maxQueueSize` items and
/// another one arrives.
enum OverflowPolicy {
  /// Drops the items that have been waiting longest, keeping the newest.
  dropOldest,

  /// Drops the items that just arrived, keeping the ones already waiting.
  dropNewest,
}

/// Creates a buffered function that collects the items passed to it and
/// invokes `onFlush` **once** with all of them, instead of once per item.
///
/// The buffer is flushed `wait` after the first item lands in it, or as soon
/// as it holds `maxSize` items, whichever comes first. The buffered function
/// comes with a [Buffer.cancel] method to discard the collected items and a
/// [Buffer.flush] method to invoke `onFlush` immediately.
///
/// Only one flush runs at a time. Items arriving while `onFlush` is working
/// collect for the next one, which goes out as soon as the current one
/// finishes rather than waiting all over again — so `wait` is how long items
/// sit for company, never a queue behind the flush ahead of them.
///
/// By default nothing is dropped and no caller is ever slowed down: this is
/// not a capacity buffer. `maxSize` caps what any one flush carries, and
/// `maxQueueSize` caps the backlog that builds up behind a slow one, shedding
/// the excess per `overflow`. Where `Debounce` and `Throttle` keep only the
/// arguments of the last call and discard the rest, a [Buffer] keeps them all.
///
/// Some examples:
///
/// Collapse a burst of per-item calls into a single request.
/// ```dart
///   final markRead = Buffer<String>(
///     (ids) => api.markAllRead(ids),
///     const Duration(milliseconds: 500),
///     maxSize: 25,
///   );
///
///   void onMessageSeen(String id) => markRead(id);
/// ```
///
/// Batch everything queued up in the current event loop turn, the way a
/// data loader does, by waiting for no time at all.
/// ```dart
///   final loadUsers = Buffer<String>(
///     (ids) => api.getUsers(ids),
///     Duration.zero,
///   );
/// ```
///
/// Keep a runaway producer from growing the buffer without bound, and log
/// what that costs.
/// ```dart
///   final trackEvent = Buffer<Event>(
///     (events) => analytics.send(events),
///     const Duration(seconds: 5),
///     maxQueueSize: 10000,
///     onDrop: (events) => log.warning('dropped ${events.length} events'),
///   );
/// ```
///
/// Send what is left before going away.
/// ```dart
///   Future<void> dispose() => markRead.flush();
/// ```
class Buffer<T> {
  /// Creates a new instance of [Buffer].
  Buffer(
    this._onFlush,
    Duration wait, {
    int? maxSize,
    int? maxQueueSize,
    OverflowPolicy overflow = OverflowPolicy.dropOldest,
    BufferErrorCallback<T>? onError,
    BufferDropCallback<T>? onDrop,
  })  : assert(
          maxSize == null || maxSize > 0,
          'maxSize must be greater than 0',
        ),
        assert(
          maxQueueSize == null || maxQueueSize > 0,
          'maxQueueSize must be greater than 0',
        ),
        _wait = wait,
        _maxSize = maxSize,
        _maxQueueSize = maxQueueSize,
        _overflow = overflow,
        _onError = onError,
        _onDrop = onDrop;

  final BufferFlushCallback<T> _onFlush;
  final Duration _wait;
  final int? _maxSize;
  final int? _maxQueueSize;
  final OverflowPolicy _overflow;
  final BufferErrorCallback<T>? _onError;
  final BufferDropCallback<T>? _onDrop;

  final _items = <T>[];
  Timer? _timer;

  // Settles when the flush running right now finishes, however it finishes.
  // Never carries its error, so a failed flush cannot wedge the queue.
  Future<void>? _inFlight;

  // Set when a buffer came due while a flush was running, so the wait is not
  // served twice over.
  var _isDue = false;

  /// The number of items waiting to get flushed.
  ///
  /// Counts what is still held. Items handed to `onFlush` are gone from here
  /// even while that flush is running.
  int get length => _items.length;

  /// True if there are items waiting to get flushed, or a flush is still
  /// running.
  bool get isPending => _timer != null || _inFlight != null;

  /// Adds [item] to the buffer, arming the flush if it is the first one in.
  void call(T item) {
    _items.add(item);
    _collect();
  }

  /// Adds every item in [items] to the buffer.
  ///
  /// With a `maxSize` set, this hands over one full buffer at a time, starting
  /// the next only once the one before it has finished. With a `maxQueueSize`
  /// set, the excess is dropped as one group rather than an item at a time.
  void addAll(Iterable<T> items) {
    _items.addAll(items);
    _collect();
  }

  /// Invokes `onFlush` with the items collected so far, and keeps going until
  /// everything held when this was called has been handed over.
  ///
  /// If a flush is already running, this waits for it too, so awaiting the
  /// result drains the buffer — which is what makes it safe to call from
  /// `dispose`. On a buffer holding nothing it waits out the running flush and
  /// no more, leaving items that arrive afterwards to their own window.
  ///
  /// Whichever call starts a flush owns its failure: one started here lands on
  /// the returned future, and one the buffer started itself goes to `onError`.
  /// So a drain that waits out a flush already running can complete normally
  /// even though that flush failed — `onError` was told instead.
  Future<void> flush() {
    if (_inFlight case final inFlight?) {
      // Already empty, so the flush running is all there is left to wait for.
      // Draining past it would cut short the window of items that have only
      // just arrived, and enrol this caller in sending them.
      if (_items.isEmpty) return inFlight;

      return inFlight.then((_) => flush());
    }

    if (_items.isEmpty) return Future.value();

    return _startFlush(report: false).then((_) => flush());
  }

  /// Discards the collected items without invoking `onFlush`.
  ///
  /// A flush already running is left alone; its items were handed over before
  /// this was called.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isDue = false;
    _items.clear();
  }

  // Shared by `call` and `addAll` so a bulk add costs one pass, and so a
  // group that overflows is reported to `onDrop` in one piece.
  void _collect() {
    if (_maxQueueSize case final maxQueueSize?
        when _items.length > maxQueueSize) {
      _dropDownTo(maxQueueSize);
    }

    _pump();
  }

  bool get _isFull {
    if (_maxSize case final maxSize?) return _items.length >= maxSize;
    return false;
  }

  // Starts a flush if one is due and none is running, otherwise arms the wait.
  // Re-entered when a flush settles, so the buffer drains one flush at a time.
  void _pump() {
    if (_items.isEmpty) return;

    if (_isDue || _isFull) {
      // One at a time. Whoever is flushing pumps again on the way out, so
      // these go as soon as it is done rather than waiting all over again.
      if (_inFlight != null) return;

      _startFlush(report: true);
      return;
    }

    // Armed even behind a running flush: the wait is how long these items are
    // willing to sit for company, not a queue behind the flush ahead of them.
    _timer ??= Timer(_wait, _onDue);
  }

  void _onDue() {
    _timer = null;
    _isDue = true;
    _pump();
  }

  // Hands the next batch over and claims the queue while it runs.
  //
  // The claim is staked before `onFlush` is invoked, because `onFlush` can add
  // items synchronously and those have to queue behind this flush rather than
  // start a second one.
  //
  // With `report`, a failure goes to `onError`; without it, the failure is
  // left on the returned future for whoever asked for the flush.
  Future<void> _startFlush({required bool report}) {
    final items = _take(_maxSize);

    // A completer rather than the flush itself: `onFlush` is invoked
    // synchronously below, so there is no future to claim the queue with until
    // after the window this is closing.
    final settled = Completer<void>();
    _inFlight = settled.future;

    final flushing = report ? _invokeAndReport(items) : _invoke(items);

    // `whenComplete` runs whichever way it ends, and `ignore` takes the error
    // off this derived future, so a failure cannot wedge the queue.
    flushing.whenComplete(() {
      _inFlight = null;
      settled.complete();

      // Only the scheduled path pumps. An explicit flush drives its own drain,
      // which is what keeps every chunk it sends answerable to its caller.
      if (report) _pump();
    }).ignore();

    return flushing;
  }

  void _dropDownTo(int maxQueueSize) {
    final excess = _items.length - maxQueueSize;
    final from = switch (_overflow) {
      OverflowPolicy.dropOldest => 0,
      OverflowPolicy.dropNewest => maxQueueSize,
    };

    final dropped = _items.sublist(from, from + excess);
    _items.removeRange(from, from + excess);

    _onDrop?.call(dropped);
  }

  // Takes up to `count` items out of the buffer, disarming the wait.
  //
  // Taken before `onFlush` is invoked, so anything added while it runs
  // collects into the next buffer instead of joining this one.
  List<T> _take(int? count) {
    _timer?.cancel();
    _timer = null;
    _isDue = false;

    final take =
        (count == null || count > _items.length) ? _items.length : count;
    final items = _items.sublist(0, take);
    _items.removeRange(0, take);
    return items;
  }

  // Hands the items over, turning whatever `onFlush` returns into a future so
  // the buffer can tell when it is done.
  Future<void> _invoke(List<T> items) async => _onFlush(items);

  // A flush the buffer started itself has no caller to hand a failure back to,
  // so it goes to `onError`. Without one it is reported to the zone, as an
  // unhandled asynchronous error would be.
  Future<void> _invokeAndReport(List<T> items) async {
    try {
      await _invoke(items);
    } catch (error, stackTrace) {
      if (_onError case final onError?) {
        onError(error, stackTrace, items);
        return;
      }
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
