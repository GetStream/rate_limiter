import 'dart:async';
import 'dart:collection';

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
/// collect for the next one, which goes out once it has come due — `wait`
/// after its own first item landed, or on reaching `maxSize` — and the running
/// flush has finished, whichever is later. A batch that came due while a flush
/// was running does not then serve its wait a second time.
///
/// By default nothing is dropped and no call ever waits on a flush already
/// running: this is not a capacity buffer. A call that reaches `maxSize` does
/// hand its batch over itself, so synchronous work in `onFlush` runs before
/// that call returns. `maxSize` caps what any one flush carries, and
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
  })  : _wait = wait,
        _maxSize = _checkPositive(maxSize, 'maxSize'),
        _maxQueueSize = _checkPositive(maxQueueSize, 'maxQueueSize'),
        _overflow = overflow,
        _onError = onError,
        _onDrop = onDrop;

  // Checked rather than asserted, because asserts are stripped in release and
  // a `maxSize` of zero is worse than a crash there: every buffer looks full
  // while each flush takes nothing out of it, so it spins sending empty
  // batches and never sends the items it holds.
  static int? _checkPositive(int? limit, String name) {
    if (limit == null || limit > 0) return limit;
    throw ArgumentError.value(limit, name, 'must be greater than zero');
  }

  final BufferFlushCallback<T> _onFlush;
  final Duration _wait;
  final int? _maxSize;
  final int? _maxQueueSize;
  final OverflowPolicy _overflow;
  final BufferErrorCallback<T>? _onError;
  final BufferDropCallback<T>? _onDrop;

  // A queue rather than a list, so taking a batch off the front and shedding
  // the oldest are both cheap. Draining N items through a list would move
  // O(N^2) elements, since every removal shifts everything behind it.
  final _items = ListQueue<T>();
  Timer? _timer;

  // Settles when the flush running right now finishes, however it finishes.
  // Never carries its error, so a failed flush cannot wedge the queue.
  Future<void>? _inFlight;

  // Set when a buffer came due while a flush was running, so the wait is not
  // served twice over.
  var _isDue = false;

  // Sequence numbers for the two ends of the queue, so a drain can tell
  // whether the items it measured have really gone rather than just counting
  // removals. Shedding the newest moves the tail back, which must not satisfy
  // a snapshot taken before those items even arrived.
  var _head = 0;
  var _tail = 0;

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
    _tail++;
    _collect();
  }

  /// Adds every item in [items] to the buffer.
  ///
  /// With a `maxSize` set, this hands over one full buffer at a time, starting
  /// the next only once the one before it has finished. With a `maxQueueSize`
  /// set, the excess is dropped as one group rather than an item at a time.
  void addAll(Iterable<T> items) {
    final held = _items.length;
    _items.addAll(items);
    _tail += _items.length - held;
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
    // Already empty, so the flush running is all there is left to wait for.
    // Draining past it would cut short the window of items that have only
    // just arrived, and enrol this caller in sending them.
    if (_items.isEmpty) return _inFlight ?? Future.value();

    return _drainUntil(_tail);
  }

  /// Discards the collected items without invoking `onFlush`.
  ///
  /// A flush already running is left alone; its items were handed over before
  /// this was called.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isDue = false;
    _head = _tail;
    _items.clear();
  }

  // Hands items over a batch at a time until everything the buffer held when
  // [target] was measured has left it, waiting out anything already running.
  //
  // Measured against what has left rather than against its own batches: a
  // flush the buffer schedules itself carries part of the same items, and
  // since that one is started from the completion handler it gets there first.
  // Counting only its own would leave a drain following a steady producer for
  // as long as one kept feeding it.
  Future<void> _drainUntil(int target) {
    if (_head >= target || _items.isEmpty) {
      // Hands back anything that arrived while this was draining. A batch of
      // its own does not pump on the way out, to keep its failures answerable
      // here, so without this those items would sit with nothing to move them.
      _pump();
      return Future.value();
    }

    if (_inFlight case final inFlight?) {
      return inFlight.then((_) => _drainUntil(target));
    }

    return _startFlush(report: false).then((_) => _drainUntil(target));
  }

  // Shared by `call` and `addAll` so a bulk add costs one pass, and so a
  // group that overflows is reported to `onDrop` in one piece.
  void _collect() {
    // Hands off what can go right now, so a group arriving all at once is not
    // capped against a batch that was never going to sit in the backlog.
    _pump();

    if (_maxQueueSize case final maxQueueSize?
        when _items.length > maxQueueSize) {
      _dropDownTo(maxQueueSize);

      // The backlog shrank, so whatever is left of it needs its own wait.
      _pump();
    }
  }

  bool get _isFull {
    if (_maxSize case final maxSize?) return _items.length >= maxSize;
    return false;
  }

  // Starts a flush if one is due and none is running, otherwise arms the wait.
  // Re-entered when a flush settles, so the buffer drains one flush at a time.
  void _pump() {
    // One at a time. Whoever is flushing pumps again on the way out, so a
    // batch that came due meanwhile goes then rather than waiting afresh.
    if (_inFlight == null && (_isDue || _isFull)) {
      // Arms the remainder itself, before the callback gets a chance to run.
      _startFlush(report: true);
      return;
    }

    _armWait();
  }

  // Starts the wait for whatever is held, so it runs from when those items
  // arrived rather than from whenever the flush ahead of them finishes.
  //
  // Does nothing when the buffer is empty, or when it is already overdue and
  // only waiting for its turn at the queue.
  void _armWait() {
    if (_items.isEmpty || _isDue) return;

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

    // Timed before the callback runs: `onFlush` may work synchronously for a
    // while, and a remainder's wait should run from now rather than from
    // whenever that work returns.
    _armWait();

    final flushing = report ? _invokeAndReport(items) : _invoke(items);

    void release() {
      _inFlight = null;
      settled.complete();
    }

    // `ignore` takes the error off this derived future, so a failure cannot
    // wedge the queue.
    flushing.then(
      (_) {
        release();

        // Only the scheduled path pumps on the way out. An explicit flush
        // drives its own drain, which is what keeps every chunk it sends
        // answerable to its caller.
        if (report) _pump();
      },
      onError: (Object _, StackTrace __) {
        release();

        // An explicit drain stops at its first failure, so without this the
        // items queued behind it would sit with nothing left to move them.
        _pump();
      },
    ).ignore();

    return flushing;
  }

  void _dropDownTo(int maxQueueSize) {
    final excess = _items.length - maxQueueSize;

    final List<T> dropped;
    switch (_overflow) {
      case OverflowPolicy.dropOldest:
        // Off the front, so a drain waiting on these can stop waiting.
        _head += excess;
        dropped = List.generate(excess, (_) => _items.removeFirst());
      case OverflowPolicy.dropNewest:
        // Off the back, so these arrived last and cannot belong to a snapshot
        // taken before them. Put back in the order they came in.
        _tail -= excess;
        dropped = List.generate(
          excess,
          (_) => _items.removeLast(),
        ).reversed.toList();
    }

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
    _head += take;
    return List.generate(take, (_) => _items.removeFirst());
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
      final onError = _onError;
      if (onError == null) {
        Zone.current.handleUncaughtError(error, stackTrace);
        return;
      }

      try {
        onError(error, stackTrace, items);
      } catch (handlerError, handlerStackTrace) {
        // Reported rather than swallowed: a handler that fails has taken the
        // requeue or the logging down with it, which is worse than the flush
        // failing in the first place.
        Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
      }
    }
  }
}
