import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

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

  // A queue, so taking a batch off the front and shedding from either end are
  // all cheap. Draining N items through a list would move O(N^2) elements,
  // since every removal from the front shifts everything behind it.
  //
  // Each item carries when it arrived and when its batch comes due, which is
  // what lets the queue answer both of the awkward questions on its own:
  // taking from the front moves the oldest sequence on, shedding from the back
  // cannot, and a remainder keeps the deadline of the items it is made of
  // rather than being given a fresh one.
  final _pending = ListQueue<_Pending<T>>();
  var _nextSeq = 0;

  Timer? _timer;

  // Set when the wait for the oldest item has run out, and cleared only once
  // the buffer is empty. A batch leaving does not un-expire the wait of what
  // is left behind, because those items are every bit as old.
  var _waitIsUp = false;

  // The flush running right now, and the sequence it starts from, so a drain
  // can tell whether it is the one carrying what that drain measured. One
  // field, because the two can never disagree if there is only one of them.
  _Running? _running;

  /// The number of items waiting to get flushed.
  ///
  /// Counts what is still held. Items handed to `onFlush` are gone from here
  /// even while that flush is running.
  int get length => _pending.length;

  /// True if there are items waiting to get flushed, or a flush is still
  /// running.
  bool get isPending => _pending.isNotEmpty || _running != null;

  /// Adds [item] to the buffer, arming the flush if it is the first one in.
  void call(T item) => addAll([item]);

  /// Adds every item in [items] to the buffer.
  ///
  /// With a `maxSize` set, this hands over one full buffer at a time, starting
  /// the next only once the one before it has finished. With a `maxQueueSize`
  /// set, the excess is dropped as one group rather than an item at a time.
  void addAll(Iterable<T> items) {
    final dueAt = clock.now().add(_wait);

    // Built before the queue is touched, and before the sequence moves on:
    // any iterable can fail part way through, and one that does must not
    // leave items behind uncounted and unscheduled.
    final incoming = <_Pending<T>>[];
    for (final item in items) {
      incoming.add((item: item, seq: _nextSeq + incoming.length, dueAt: dueAt));
    }

    _nextSeq += incoming.length;
    _pending.addAll(incoming);
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
    if (_pending.isEmpty) return _running?.settled ?? Future.value();

    return _drainThrough(_pending.last.seq);
  }

  /// Discards the collected items without invoking `onFlush`.
  ///
  /// A flush already running is left alone; its items were handed over before
  /// this was called.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _waitIsUp = false;
    _pending.clear();
  }

  // Hands batches over until the item that arrived at [through] has left the
  // buffer, and the flush carrying it has finished.
  //
  // Measured by sequence rather than by counting batches, because the buffer
  // schedules flushes of its own from a completion handler and so gets to the
  // queue first: counting only its own batches would leave a drain following
  // a steady producer for as long as one kept feeding it.
  Future<void> _drainThrough(int through) {
    if (_pending.isEmpty || _pending.first.seq > through) {
      // Gone from the buffer, but a flush still running may be the one
      // carrying it, and this has to outlast that to be worth awaiting.
      if (_running case final running? when running.from <= through) {
        return running.settled.then((_) => _drainThrough(through));
      }

      // Hands back anything that arrived while this was draining. A batch of
      // its own does not pump on the way out, to keep its failures answerable
      // here, so without this those items would sit with nothing to move them.
      _pump();
      return Future.value();
    }

    if (_running case final running?) {
      return running.settled.then((_) => _drainThrough(through));
    }

    return _startFlush(report: false).then((_) => _drainThrough(through));
  }

  // Shared by `call` and `addAll` so a bulk add costs one pass, and so a
  // group that overflows is reported to `onDrop` in one piece.
  void _collect() {
    // Hands off what can go right now, so a group arriving all at once is not
    // capped against a batch that was never going to sit in the backlog.
    _pump();

    if (_maxQueueSize case final maxQueueSize?
        when _pending.length > maxQueueSize) {
      final shed = _shedDownTo(maxQueueSize);

      // The backlog shrank, so whatever is left of it needs its own wait —
      // settled before `onDrop`, which is free to throw.
      _pump();

      _onDrop?.call(shed);
    }
  }

  bool get _isFull {
    if (_maxSize case final maxSize?) return _pending.length >= maxSize;
    return false;
  }

  // Starts a flush if one is due and none is running, otherwise arms the wait.
  // Re-entered when a flush settles, so the buffer drains one at a time.
  void _pump() {
    if (_pending.isEmpty) return;

    // One at a time. Whoever is flushing pumps again on the way out, so a
    // batch that came due meanwhile goes then rather than waiting afresh.
    if (_running == null && (_waitIsUp || _isFull)) {
      // Arms whatever is left over itself, before the callback can run.
      _startFlush(report: true);
      return;
    }

    _armWait();
  }

  // The wait belongs to whoever is at the front, so a head that has left takes
  // its wait with it: the timer was armed for its deadline, and a wait that
  // ran out for it says nothing about an item that arrived later.
  void _rewindWait() {
    _timer?.cancel();
    _timer = null;
    _waitIsUp =
        _pending.isNotEmpty && !clock.now().isBefore(_pending.first.dueAt);
  }

  // Waits out the oldest item's deadline, which is carried by the item rather
  // than by the batch, so what is left behind is not given a fresh window.
  //
  // Nothing to arm if the buffer is empty, if a wait is already running, or if
  // one has already run out and is only waiting its turn at the queue.
  void _armWait() {
    if (_pending.isEmpty || _timer != null || _waitIsUp) return;

    final due = _pending.first.dueAt.difference(clock.now());
    _timer = Timer(due, _onDue);
  }

  void _onDue() {
    _timer = null;
    _waitIsUp = true;
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
    final from = _pending.first.seq;
    final items = _take(_maxSize);

    // A completer rather than the flush itself: `onFlush` is invoked
    // synchronously below, so there is no future to claim the queue with until
    // after the window this is closing.
    final settled = Completer<void>();
    _running = (settled: settled.future, from: from);

    // Timed before the callback runs: `onFlush` may work synchronously for a
    // while, and a remainder should not be waiting on that work to return.
    _armWait();

    final flushing = report ? _invokeAndReport(items) : _invoke(items);

    void release() {
      _running = null;
      settled.complete();
    }

    // `ignore` takes the error off this derived future, so a failure cannot
    // wedge the queue.
    flushing.then(
      (_) {
        release();

        // Only the scheduled path pumps on the way out. An explicit flush
        // drives its own drain, which is what keeps every batch it sends
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

  // Sheds down to [maxQueueSize] and hands back what went, for the caller to
  // report once scheduling has been settled.
  List<T> _shedDownTo(int maxQueueSize) {
    final excess = _pending.length - maxQueueSize;

    final List<_Pending<T>> shed;
    switch (_overflow) {
      case OverflowPolicy.dropOldest:
        shed = List.generate(excess, (_) => _pending.removeFirst());
        _rewindWait();
      case OverflowPolicy.dropNewest:
        // Off the back, so these arrived last, which is why shedding them can
        // never settle a drain measured before they turned up, and why the
        // wait at the front is untouched. Handed over in arrival order.
        shed = List.generate(
          excess,
          (_) => _pending.removeLast(),
        ).reversed.toList();
    }

    return [for (final pending in shed) pending.item];
  }

  // Takes up to `count` items off the front, disarming the wait. Taken before
  // `onFlush` is invoked, so anything added while it runs collects into the
  // next batch instead of joining this one.
  List<T> _take(int? count) {
    final take =
        (count == null || count > _pending.length) ? _pending.length : count;
    final taken = List.generate(take, (_) => _pending.removeFirst().item);

    _rewindWait();

    return taken;
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

// One item, with the sequence it arrived at and the moment its batch is due.
typedef _Pending<T> = ({T item, int seq, DateTime dueAt});

// A flush in progress: a future that settles either way, and the sequence of
// the first item it is carrying.
typedef _Running = ({Future<void> settled, int from});
