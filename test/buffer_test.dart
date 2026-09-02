import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('buffer', () {
    test('should invoke onFlush once with everything collected', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        buffered('a');
        buffered('b');
        buffered('c');

        expect(flushes, isEmpty);
        expect(buffered.length, 3);

        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b', 'c'],
        ]);
      });
    });

    test('should measure the wait from the first item, not the last', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        buffered('a');
        async.elapse(20.toDuration());

        // A later item rides the deadline already set; it does not push it out
        // the way another debounced call would.
        buffered('b');
        async.elapse(12.toDuration());

        expect(flushes, [
          ['a', 'b'],
        ]);
      });
    });

    test('should open a new buffer for the items after a flush', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        buffered('a');
        async.elapse(32.toDuration());

        buffered('b');
        expect(buffered.isPending, isTrue);
        async.elapse(32.toDuration());

        expect(flushes, [
          ['a'],
          ['b'],
        ]);
      });
    });

    test('should flush as soon as it holds maxSize items', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxSize: 2,
        );

        buffered('a');
        buffered('b');

        // Full, so it went without waiting out the rest of the window.
        expect(flushes, [
          ['a', 'b'],
        ]);
        expect(buffered.isPending, isTrue,
            reason: 'the flush is still running');

        async.flushMicrotasks();
        expect(buffered.isPending, isFalse);

        buffered('c');
        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b'],
          ['c'],
        ]);
      });
    });

    test('should batch a burst from a single event loop turn', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, Duration.zero);

        buffered('a');
        buffered('b');
        buffered('c');

        expect(flushes, isEmpty, reason: 'the burst has not finished yet');

        async.elapse(Duration.zero);

        expect(flushes, [
          ['a', 'b', 'c'],
        ]);
      });
    });

    test('should fill as many buffers as addAll has items for', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];

        final buffered = buffer<int>(
          flushes.add,
          32.toDuration(),
          maxSize: 2,
        );

        buffered.addAll([1, 2, 3, 4, 5]);

        // One at a time: the second buffer waits for the first to finish.
        expect(flushes, [
          [1, 2],
        ]);

        async.flushMicrotasks();
        expect(flushes, [
          [1, 2],
          [3, 4],
        ]);
        expect(buffered.length, 1, reason: 'the remainder waits its turn');

        async.elapse(32.toDuration());

        expect(flushes, [
          [1, 2],
          [3, 4],
          [5],
        ]);
      });
    });

    test('should fill the buffer already open when addAll arrives', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];

        final buffered = buffer<int>(
          flushes.add,
          32.toDuration(),
          maxSize: 2,
        );

        buffered(1);
        buffered.addAll([2, 3, 4]);
        async.flushMicrotasks();

        expect(flushes, [
          [1, 2],
          [3, 4],
        ]);
        expect(buffered.length, 0);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should keep collecting after a flush fails', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        var failNextFlush = true;

        final buffered = buffer<String>(
          (items) {
            flushes.add(items);
            if (failNextFlush) {
              failNextFlush = false;
              throw Exception('flush failed');
            }
          },
          32.toDuration(),
          maxSize: 2,
          onError: (e, s, items) {},
        );

        buffered('a');
        buffered('b');

        expect(flushes, [
          ['a', 'b'],
        ]);
        expect(buffered.length, 0);

        buffered('c');
        expect(
          buffered.isPending,
          isTrue,
          reason: 'a failed flush must not wedge the buffer',
        );

        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b'],
          ['c'],
        ]);
      });
    });

    test('should flush every item when maxSize is one', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxSize: 1,
        );

        buffered('a');
        buffered('b');
        async.flushMicrotasks();

        expect(flushes, [
          ['a'],
          ['b'],
        ]);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should drop the oldest items once maxQueueSize is reached', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final drops = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 3,
          onDrop: drops.add,
        );

        buffered.addAll(['a', 'b', 'c']);
        buffered('d');

        expect(drops, [
          ['a'],
        ]);
        expect(buffered.length, 3);

        async.elapse(32.toDuration());

        expect(
            flushes,
            [
              ['b', 'c', 'd'],
            ],
            reason: 'the dropped item never reached onFlush');
      });
    });

    test('should drop what just arrived when told to keep the oldest', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final drops = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 3,
          overflow: OverflowPolicy.dropNewest,
          onDrop: drops.add,
        );

        buffered.addAll(['a', 'b', 'c']);
        buffered('d');

        expect(drops, [
          ['d'],
        ]);

        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b', 'c'],
        ]);
      });
    });

    test('should report an overflowing group as one drop', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final drops = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 3,
          onDrop: drops.add,
        );

        buffered('a');
        buffered.addAll(['b', 'c', 'd', 'e']);

        // Reported in one piece, rather than once per item over-the-line.
        expect(drops, [
          ['a', 'b'],
        ]);

        async.elapse(32.toDuration());

        expect(flushes, [
          ['c', 'd', 'e'],
        ]);
      });
    });

    test('should keep the waiting items when dropping the newest', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final drops = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 2,
          overflow: OverflowPolicy.dropNewest,
          onDrop: drops.add,
        );

        buffered('a');
        buffered.addAll(['b', 'c', 'd']);

        // 'a' has been waiting, so it survives an incoming group too big to
        // fit alongside it.
        expect(drops, [
          ['c', 'd'],
        ]);

        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b'],
        ]);
      });
    });

    test('should keep only the newest when a group dwarfs maxQueueSize', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];
        final drops = <List<int>>[];

        final buffered = buffer<int>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 2,
          onDrop: drops.add,
        );

        buffered.addAll([1, 2, 3, 4, 5]);

        expect(drops, [
          [1, 2, 3],
        ]);
        expect(buffered.length, 2);

        async.elapse(32.toDuration());

        expect(flushes, [
          [4, 5],
        ]);
      });
    });

    test('should drop without an onDrop to report to', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(
          flushes.add,
          32.toDuration(),
          maxQueueSize: 2,
        );

        buffered.addAll(['a', 'b', 'c']);
        async.elapse(32.toDuration());

        expect(flushes, [
          ['b', 'c'],
        ]);
      });
    });

    test('should discard the collected items on cancel', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        buffered('a');
        buffered('b');
        buffered.cancel();

        expect(buffered.length, 0);
        expect(buffered.isPending, isFalse);

        // Past the deadline, so `cancel` is what stopped it.
        async.elapse(128.toDuration());

        expect(flushes, isEmpty);
      });
    });

    test('should never have two flushes running at once', () {
      fakeAsync((async) {
        final started = <List<String>>[];
        final blockers = <Completer<void>>[];
        var running = 0;
        var mostAtOnce = 0;

        final buffered = buffer<String>(
          (items) {
            started.add(items);
            running++;
            mostAtOnce = running > mostAtOnce ? running : mostAtOnce;
            final blocker = Completer<void>();
            blockers.add(blocker);
            return blocker.future.whenComplete(() => running--);
          },
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration());

        buffered('b');
        async.elapse(32.toDuration());

        buffered('c');
        async.elapse(32.toDuration());

        expect(
            started,
            [
              ['a'],
            ],
            reason: "'b' and 'c' waited behind the flush carrying 'a'");
        expect(mostAtOnce, 1);
        expect(buffered.isPending, isTrue);

        for (final blocker in blockers.toList()) {
          blocker.complete();
        }
        async.elapse(32.toDuration());

        expect(
            started,
            [
              ['a'],
              ['b', 'c'],
            ],
            reason: 'the two that waited went together');
        expect(mostAtOnce, 1);
      });
    });

    test('should not let onFlush start a second flush from inside itself', () {
      fakeAsync((async) {
        final started = <List<String>>[];
        var running = 0;
        var mostAtOnce = 0;
        var reentered = false;

        late final Buffer<String> buffered;
        buffered = buffer<String>(
          (items) {
            started.add(items);
            running++;
            mostAtOnce = running > mostAtOnce ? running : mostAtOnce;

            if (!reentered) {
              reentered = true;
              // Re-entrant, and maxSize of one makes it due immediately. The
              // claim on the queue has to be staked before we get here.
              buffered('b');
            }

            return Future<void>.delayed(10.toDuration(), () => running--);
          },
          32.toDuration(),
          maxSize: 1,
        );

        buffered('a');

        expect(
            started,
            [
              ['a'],
            ],
            reason: "'b' has to wait its turn");
        expect(mostAtOnce, 1);

        async.elapse(100.toDuration());

        expect(started, [
          ['a'],
          ['b'],
        ]);
        expect(mostAtOnce, 1);
      });
    });

    test('should hold a remainder to its own deadline, not the flush ahead',
        () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final flushes = <List<int>>[];

        final buffered = buffer<int>(
          (items) {
            flushes.add(items);
            return flushes.length == 1 ? blocker.future : null;
          },
          500.toDuration(),
          maxSize: 2,
        );

        // [1, 2] fills a batch and goes; 3 stays behind with its own window
        // running from now.
        buffered.addAll([1, 2, 3]);

        expect(flushes, [
          [1, 2],
        ]);

        // The batch ahead of it takes far longer than that window.
        async.elapse(2000.toDuration());
        expect(flushes.length, 1, reason: 'still waiting for the queue');

        blocker.complete();
        async.flushMicrotasks();

        expect(
            flushes,
            [
              [1, 2],
              [3],
            ],
            reason: '3 was overdue, so it went as soon as its turn came');
      });
    });

    test('should go straight out when a wait was served during a flush', () {
      fakeAsync((async) {
        final started = <List<String>>[];
        final blocker = Completer<void>();

        final buffered = buffer<String>(
          (items) {
            started.add(items);
            return started.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration()); // flush of 'a' starts and blocks

        buffered('b');
        async.elapse(32.toDuration()); // 'b' comes due, but has to wait

        expect(started, [
          ['a'],
        ]);

        blocker.complete();
        async.flushMicrotasks();

        // No second wait: 'b' was already overdue when the flush finished.
        expect(started, [
          ['a'],
          ['b'],
        ]);
      });
    });

    test('should report itself as pending while a flush is running', () {
      fakeAsync((async) {
        final blocker = Completer<void>();

        final buffered = buffer<String>(
          (items) => blocker.future,
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration());

        expect(buffered.length, 0, reason: 'handed over');
        expect(buffered.isPending, isTrue, reason: 'but not done');

        blocker.complete();
        async.flushMicrotasks();

        expect(buffered.isPending, isFalse);
      });
    });

    test('should let flush await the one already running', () {
      fakeAsync((async) {
        final started = <List<String>>[];
        final blocker = Completer<void>();
        var drained = false;

        final buffered = buffer<String>(
          (items) {
            started.add(items);
            return started.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration()); // flush of 'a' starts and blocks

        buffered('b');
        buffered.flush().then((_) => drained = true).ignore();
        async.flushMicrotasks();

        expect(drained, isFalse, reason: 'the flush carrying a is still going');
        expect(started, [
          ['a'],
        ]);

        blocker.complete();
        async.flushMicrotasks();

        expect(started, [
          ['a'],
          ['b'],
        ]);
        expect(drained, isTrue, reason: 'and everything after it went too');
      });
    });

    test('should drain every full buffer on flush', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];
        var drained = false;

        final buffered = buffer<int>(
          flushes.add,
          32.toDuration(),
          maxSize: 2,
        );

        buffered.addAll([1, 2, 3, 4, 5]);
        buffered.flush().then((_) => drained = true).ignore();
        async.flushMicrotasks();

        expect(
            flushes,
            [
              [1, 2],
              [3, 4],
              [5],
            ],
            reason: 'flush keeps going until nothing is held');
        expect(drained, isTrue);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should keep the queue moving when a flush fails', () {
      fakeAsync((async) {
        final started = <List<String>>[];
        final blocker = Completer<void>();

        final buffered = buffer<String>(
          (items) {
            started.add(items);
            return started.length == 1
                ? blocker.future.then((_) => throw Exception('flush failed'))
                : null;
          },
          32.toDuration(),
          onError: (e, s, items) {},
        );

        buffered('a');
        async.elapse(32.toDuration());

        buffered('b');
        blocker.complete();
        async.elapse(32.toDuration());

        expect(
            started,
            [
              ['a'],
              ['b'],
            ],
            reason: 'a failure must not wedge what is queued behind it');
        expect(buffered.isPending, isFalse);
      });
    });

    test('should keep the queue moving when an explicit flush fails', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final flushes = <List<String>>[];

        final buffered = buffer<String>(
          (items) {
            flushes.add(items);
            return flushes.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
          maxSize: 2,
          onError: (e, s, items) {},
        );

        buffered('a');
        buffered.flush().then((_) {}, onError: (Object _) {}).ignore();

        // One call, so this goes straight to the full branch and never arms a
        // wait of its own. The failed drain is all that could move it.
        buffered.addAll(['b', 'c']);

        blocker.completeError(Exception('flush failed'));
        async.flushMicrotasks();

        expect(
            flushes,
            [
              ['a'],
              ['b', 'c'],
            ],
            reason: 'a failed drain must not strand what queued behind it');
        expect(buffered.length, 0);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should send what it can before capping the backlog', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];
        final drops = <List<int>>[];
        final blocker = Completer<void>();

        final buffered = buffer<int>(
          (items) {
            flushes.add(items);
            return blocker.future;
          },
          32.toDuration(),
          maxSize: 2,
          maxQueueSize: 3,
          onDrop: drops.add,
        );

        buffered.addAll([1, 2, 3, 4, 5, 6]);

        // Nothing was running, so [1, 2] takes the batch and only what is
        // genuinely backlog gets measured against maxQueueSize.
        expect(flushes, [
          [1, 2],
        ]);
        expect(drops, [
          [3],
        ]);
        expect(buffered.length, 3);
      });
    });

    test('should wait out the running flush and no more when empty', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final flushes = <List<int>>[];
        var drained = false;

        final buffered = buffer<int>(
          (items) {
            flushes.add(items);
            return flushes.length == 1 ? blocker.future : null;
          },
          1000.toDuration(),
        );

        buffered(1);
        async.elapse(1000.toDuration()); // the flush of 1 starts and blocks
        expect(buffered.length, 0, reason: 'handed over already');

        buffered.flush().then((_) => drained = true).ignore();

        // Arrives after the drain was asked for, with its window still to run.
        buffered(2);

        blocker.complete();
        async.flushMicrotasks();

        expect(drained, isTrue);
        expect(
            flushes,
            [
              [1],
            ],
            reason: 'the window of 2 was not cut short by an unrelated flush');
        expect(buffered.length, 1);
      });
    });

    test('should outlast the flush that carries what it measured', () {
      fakeAsync((async) {
        final first = Completer<void>();
        final second = Completer<void>();
        final started = <List<String>>[];
        var drained = false;

        final buffered = buffer<String>(
          (items) {
            started.add(items);
            return started.length == 1 ? first.future : second.future;
          },
          32.toDuration(),
          maxSize: 2,
        );

        buffered.addAll(['a', 'b']); // goes at once, and blocks
        buffered.addAll(['c', 'd']); // the snapshot
        buffered.flush().then((_) => drained = true).ignore();

        // Its completion handler starts [c, d], so the snapshot has left the
        // buffer — but into a flush that has not finished.
        first.complete();
        async.flushMicrotasks();

        expect(started, [
          ['a', 'b'],
          ['c', 'd'],
        ]);
        expect(drained, isFalse, reason: 'awaiting it must mean it is sent');

        second.complete();
        async.flushMicrotasks();

        expect(drained, isTrue);
      });
    });

    test('should not let a shed item take the wait of what replaced it', () {
      fakeAsync((async) {
        final sentAt = <int>[];

        final buffered = buffer<String>(
          (items) => sentAt.add(async.elapsed.inMilliseconds),
          32.toDuration(),
          maxQueueSize: 2,
        );

        buffered('a'); // due at t=32
        async.elapse(16.toDuration());

        // Sheds 'a', so the wait armed for it belongs to nobody. What is left
        // arrived at t=16 and is due at t=48.
        buffered.addAll(['b', 'c']);
        async.elapse(200.toDuration());

        expect(sentAt, [48]);
      });
    });

    test('should not hand a later item an expired wait when batching', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final sentAt = <int>[];

        final buffered = buffer<int>(
          (items) {
            sentAt.add(async.elapsed.inMilliseconds);
            return sentAt.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
          maxSize: 2,
        );

        buffered(0);
        async.elapse(32.toDuration()); // sends [0], and blocks

        buffered(1); // due at t=64
        async.elapse(40.toDuration()); // t=72, so 1 is overdue

        buffered.addAll([2, 3]); // due at t=104
        blocker.complete();
        async.elapse(500.toDuration());

        // [1, 2] goes as soon as the queue frees, since 1 was overdue. 3 was
        // not, and must not inherit the wait that ran out for 1.
        expect(sentAt, [32, 72, 104]);
      });
    });

    test('should keep a remainder to its deadline across full batches', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final sentAt = <int>[];

        final buffered = buffer<int>(
          (items) {
            sentAt.add(async.elapsed.inMilliseconds);
            return sentAt.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
          maxSize: 2,
        );

        // All five arrive together, so all five are due at t=32.
        buffered.addAll([1, 2, 3, 4, 5]);
        async.elapse(100.toDuration());

        blocker.complete();
        async.elapse(500.toDuration());

        // The odd one out is overdue by the time its turn comes, so it goes
        // then rather than starting a window of its own.
        expect(sentAt, [0, 100, 100]);
      });
    });

    test('should leave the buffer alone when an iterable fails part way', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];
        final buffered = buffer<int>(flushes.add, 32.toDuration());

        expect(
          () => buffered.addAll(_failsAfter(3)),
          throwsA(isA<StateError>()),
        );

        expect(buffered.length, 0, reason: 'nothing half-added');
        expect(buffered.isPending, isFalse);

        async.elapse(128.toDuration());
        expect(flushes, isEmpty);
      });
    });

    test('should not let shedding the newest satisfy a drain', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final sent = <List<String>>[];
        var drained = false;

        final buffered = buffer<String>(
          (items) {
            sent.add(items);
            return sent.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
          maxQueueSize: 2,
          overflow: OverflowPolicy.dropNewest,
        );

        buffered('z');
        async.elapse(32.toDuration()); // the flush of z starts, and blocks

        buffered.addAll(['a', 'b']);
        buffered.flush().then((_) => drained = true).ignore();

        // Over the cap, so these are shed. They arrived after the drain took
        // its measure, so shedding them settles nothing it was waiting for.
        buffered.addAll(['c', 'd']);

        blocker.complete();
        async.flushMicrotasks();

        expect(sent, [
          ['z'],
          ['a', 'b'],
        ]);
        expect(drained, isTrue, reason: 'and only once its own items went');
        expect(buffered.length, 0);
      });
    });

    test('should hand back what came due behind a slow drain', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final sent = <List<String>>[];

        final buffered = buffer<String>(
          (items) {
            sent.add(items);
            return sent.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
        );

        buffered('a');
        buffered.flush().ignore(); // takes a, and blocks

        buffered('b');
        async.elapse(50.toDuration()); // b comes due while the drain runs

        blocker.complete();
        async.flushMicrotasks();

        // The drain is finished, so what it was not measuring has to go back
        // under the buffer's own ownership rather than sit unowned.
        expect(sent, [
          ['a'],
          ['b'],
        ]);
        expect(buffered.length, 0);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should not follow a producer past the batch it measured', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        final sent = <List<String>>[];
        var drained = false;

        final buffered = buffer<String>(
          (items) {
            sent.add(items);
            return sent.length == 1 ? blocker.future : null;
          },
          32.toDuration(),
          maxSize: 2,
        );

        buffered.addAll(['a', 'b']); // goes at once, and blocks
        buffered.addAll(['c', 'd']); // what the drain takes the measure of

        buffered.flush().then((_) => drained = true).ignore();

        // Arrives after that measure, and on its own is not a full batch, so
        // only a drain that overreached would send it.
        buffered('e');

        blocker.complete();
        async.flushMicrotasks();

        // The buffer schedules [c, d] itself from the completion handler, so
        // the drain never sends a batch of its own — it is done all the same.
        expect(sent, [
          ['a', 'b'],
          ['c', 'd'],
        ]);
        expect(drained, isTrue, reason: 'its batch is gone, whoever sent it');
        expect(buffered.length, 1, reason: 'e is the buffer\'s own work');
      });
    });

    test('should not enrol a flush in what arrives mid-drain', () {
      fakeAsync((async) {
        final blocker = Completer<void>();
        var calls = 0;
        Object? caughtByFlush;
        Object? caughtByOnError;
        var drained = false;

        final buffered = buffer<String>(
          (items) {
            calls++;
            if (calls == 1) return blocker.future;
            throw Exception('the later batch failed');
          },
          32.toDuration(),
          maxSize: 2,
          onError: (e, s, items) => caughtByOnError = e,
        );

        buffered('a');
        buffered.flush().then((_) => drained = true, onError: (Object e) {
          caughtByFlush = e;
        }).ignore();

        // Arriving after the drain took its measure, so these are the
        // buffer's own work rather than the caller's.
        buffered('b');
        buffered('c');

        blocker.complete();
        async.elapse(32.toDuration());

        expect(calls, 2);
        expect(drained, isTrue, reason: 'the one item it took went out');
        expect(caughtByFlush, isNull, reason: 'the caller did not send those');
        expect(caughtByOnError, isNotNull, reason: 'so the buffer answers');
      });
    });

    test('should leave a flush it only waited for to onError', () {
      fakeAsync((async) {
        var calls = 0;
        Object? caughtByFlush;
        Object? caughtByOnError;
        var drained = false;

        final buffered = buffer<int>(
          (items) {
            calls++;
            if (calls == 2) throw Exception('the second chunk failed');
          },
          32.toDuration(),
          maxSize: 2,
          onError: (e, s, items) => caughtByOnError = e,
        );

        // Two full buffers, so the buffer schedules both chunks itself and
        // flush only waits them out.
        buffered.addAll([1, 2, 3, 4]);
        buffered.flush().then((_) {
          drained = true;
        }, onError: (Object e) {
          caughtByFlush = e;
        }).ignore();

        async.elapse(32.toDuration());

        expect(calls, 2);
        expect(caughtByOnError, isNotNull, reason: 'the buffer sent it');
        expect(caughtByFlush, isNull);
        expect(drained, isTrue,
            reason: 'the buffer did drain, and it is empty');
        expect(buffered.length, 0);
      });
    });

    test('should collect again after being cancelled', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        expect(buffered.isPending, isFalse);
        buffered.cancel();

        buffered('a');
        buffered.cancel();

        buffered('b');
        async.elapse(32.toDuration());

        expect(
            flushes,
            [
              ['b'],
            ],
            reason: 'cancel drops what is held, it does not stop the buffer');
      });
    });

    test('should leave a flush already on its way out alone on cancel', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final completer = Completer<void>();

        final buffered = buffer<String>(
          (items) {
            flushes.add(items);
            return completer.future;
          },
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration());

        buffered('b');
        buffered.cancel();
        completer.complete();
        async.elapse(32.toDuration());

        expect(
            flushes,
            [
              ['a'],
            ],
            reason: 'the in-flight items were already handed over');
      });
    });

    test('should invoke onFlush immediately on flush', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        final buffered = buffer<String>(flushes.add, 32.toDuration());

        buffered('a');
        buffered.flush().ignore();
        async.flushMicrotasks();

        expect(flushes, [
          ['a'],
        ]);
        expect(buffered.isPending, isFalse);

        // The timer it left behind would flush an empty buffer, or worse,
        // report itself as pending again.
        async.elapse(128.toDuration());

        expect(flushes, [
          ['a'],
        ]);
      });
    });

    test('should complete flush once onFlush does', () {
      fakeAsync((async) {
        final completer = Completer<void>();
        var flushed = false;

        final buffered = buffer<String>(
          (items) => completer.future,
          32.toDuration(),
        );

        buffered('a');
        buffered.flush().then((_) => flushed = true).ignore();
        async.elapse(128.toDuration());

        expect(flushed, isFalse, reason: 'onFlush has not finished');

        completer.complete();
        async.flushMicrotasks();

        expect(flushed, isTrue);
      });
    });

    test('should do nothing when flushing an empty buffer', () {
      fakeAsync((async) {
        var callCount = 0;

        final buffered =
            buffer<String>((items) => callCount++, 32.toDuration());

        buffered.flush().ignore();
        buffered.addAll(const []);
        async.elapse(128.toDuration());

        expect(callCount, 0);
        expect(buffered.isPending, isFalse);
      });
    });

    test('should collect what arrives while onFlush is running', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final completer = Completer<void>();

        final buffered = buffer<String>(
          (items) {
            flushes.add(items);
            return completer.future;
          },
          32.toDuration(),
        );

        buffered('a');
        async.elapse(32.toDuration());

        // Joining the buffer being flushed would hand these to a request
        // already on its way out.
        buffered('b');
        completer.complete();
        async.elapse(32.toDuration());

        expect(flushes, [
          ['a'],
          ['b'],
        ]);
      });
    });

    test('should hand a scheduled failure to onError', () {
      fakeAsync((async) {
        final error = Exception('flush failed');
        Object? caughtError;
        List<String>? caughtItems;

        final buffered = buffer<String>(
          (items) => throw error,
          32.toDuration(),
          onError: (e, s, items) {
            caughtError = e;
            caughtItems = items;
          },
        );

        buffered('a');
        buffered('b');
        async.elapse(32.toDuration());

        expect(caughtError, error);
        // Handed back so they can be re-queued rather than lost.
        expect(caughtItems, ['a', 'b']);
      });
    });

    test('should give a failure to the caller that asked for the flush', () {
      fakeAsync((async) {
        final error = Exception('flush failed');
        Object? caughtByFlush;
        Object? caughtByOnError;

        final buffered = buffer<String>(
          (items) async => throw error,
          32.toDuration(),
          onError: (e, s, items) => caughtByOnError = e,
        );

        buffered('a');
        buffered.flush().onError((e, s) => caughtByFlush = e);
        async.flushMicrotasks();

        expect(caughtByFlush, error);
        expect(
          caughtByOnError,
          isNull,
          reason: 'the caller was told, so onError has nothing to report',
        );
      });
    });

    test('should report a scheduled failure with no onError to the zone', () {
      final error = Exception('flush failed');
      final caught = Completer<Object>();

      return runZonedGuarded(() async {
        final buffered = buffer<String>(
          (items) async => throw error,
          Duration.zero,
        );

        buffered('a');

        expect(await caught.future, error);
      }, (e, s) {
        if (!caught.isCompleted) caught.complete(e);
      });
    });

    test('should report an onError that fails itself to the zone', () {
      final caught = Completer<Object>();

      return runZonedGuarded(() async {
        final buffered = buffer<String>(
          (items) async => throw Exception('flush failed'),
          Duration.zero,
          // Takes the requeue down with it, so it cannot be swallowed.
          onError: (e, s, items) => throw StateError('the handler failed too'),
        );

        buffered('a');

        expect(await caught.future, isA<StateError>());
      }, (e, s) {
        if (!caught.isCompleted) caught.complete(e);
      });
    });

    test('should convert an existing function into a buffered one', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        void markAllRead(List<String> ids) => flushes.add(ids);

        final buffered = markAllRead.buffered(32.toDuration(), maxSize: 3);

        buffered('a');
        buffered('b');
        async.elapse(32.toDuration());

        expect(flushes, [
          ['a', 'b'],
        ]);
      });
    });

    test('should carry every option through the extension', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];
        final drops = <List<String>>[];

        void markAllRead(List<String> ids) => flushes.add(ids);

        final buffered = markAllRead.buffered(
          32.toDuration(),
          maxQueueSize: 2,
          overflow: OverflowPolicy.dropNewest,
          onDrop: drops.add,
        );

        buffered.addAll(['a', 'b', 'c']);
        async.elapse(32.toDuration());

        expect(drops, [
          ['c'],
        ]);
        expect(flushes, [
          ['a', 'b'],
        ]);
      });
    });

    test('should hold its invariants whatever order it is driven in', () {
      // What this is really for: whatever order the buffer is driven in, it
      // drains once you stop feeding it, and it never hands over more than it
      // was told to. Asserting `isPending` here would prove nothing, since it
      // reads the queue and so is true by definition wherever items are held.
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        final byMaxSize = rng.nextBool();
        final limit = 1 + rng.nextInt(4);

        // Half the seeds flush slowly, so items come due while a flush is
        // still running. Every strand bug so far has hidden in that window.
        final slowFlush = rng.nextBool();

        fakeAsync((async) {
          final flushes = <List<int>>[];
          final buffered = Buffer<int>(
            (items) {
              flushes.add(items);
              return slowFlush ? Future<void>.delayed(25.toDuration()) : null;
            },
            10.toDuration(),
            maxSize: byMaxSize ? limit : null,
            maxQueueSize: byMaxSize ? null : limit,
          );

          void checkInvariants(String op) {
            final where = 'seed $seed, after $op';

            // `maxSize` bounds each flush, not the buffer: items pile up
            // behind a running flush. Only `maxQueueSize` caps what is held.
            if (!byMaxSize) {
              expect(
                buffered.length,
                lessThanOrEqualTo(limit),
                reason: '$where: held more than maxQueueSize allows',
              );
            }
          }

          var next = 0;
          for (var step = 0; step < 30; step++) {
            switch (rng.nextInt(5)) {
              case 0:
                buffered(next++);
                checkInvariants('call');
              case 1:
                buffered.addAll(List.generate(rng.nextInt(6), (_) => next++));
                checkInvariants('addAll');
              case 2:
                buffered.flush().ignore();
                checkInvariants('flush');
              case 3:
                buffered.cancel();
                checkInvariants('cancel');
              case 4:
                async.elapse(rng.nextInt(20).toDuration());
                checkInvariants('elapse');
            }
          }

          // Nothing more goes in, so everything held has to find its way out.
          // A buffer that never armed a timer, or that dropped a wait when the
          // head moved, is stuck here rather than merely late.
          async.elapse(const Duration(minutes: 1));

          expect(
            buffered.length,
            0,
            reason: 'seed $seed: stopped feeding it and it never drained',
          );
          expect(buffered.isPending, isFalse, reason: 'seed $seed');

          for (final flush in flushes) {
            expect(flush, isNotEmpty, reason: 'seed $seed: flushed nothing');
            if (byMaxSize) {
              expect(
                flush.length,
                lessThanOrEqualTo(limit),
                reason: 'seed $seed: handed over more than maxSize',
              );
            }
          }
        });
      }
    });

    // Thrown rather than asserted: asserts are stripped in release, and a
    // maxSize of zero leaves the buffer spinning on empty flushes there.
    test('should reject a maxSize that can never fill', () {
      expect(
        () => Buffer<int>((items) {}, Duration.zero, maxSize: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject a maxQueueSize that can never hold anything', () {
      expect(
        () => Buffer<int>((items) {}, Duration.zero, maxQueueSize: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should cap the batch and the backlog independently', () {
      fakeAsync((async) {
        final flushes = <List<int>>[];
        final drops = <List<int>>[];
        final blocker = Completer<void>();

        // maxSize caps what one flush carries; maxQueueSize caps what may pile
        // up behind it. Serialized flushes are what make both reachable.
        final buffered = buffer<int>(
          (items) {
            flushes.add(items);
            return blocker.future;
          },
          32.toDuration(),
          maxSize: 2,
          maxQueueSize: 3,
          onDrop: drops.add,
        );

        buffered.addAll([1, 2]);

        expect(
          flushes,
          [
            [1, 2],
          ],
          reason: 'full, so one flush carrying maxSize items',
        );

        // These pile up behind the running flush, and that backlog is what
        // maxQueueSize caps.
        buffered.addAll([3, 4, 5, 6]);

        expect(buffered.length, 3);
        expect(drops, [
          [3],
        ]);

        blocker.complete();
        async.elapse(32.toDuration());

        expect(flushes, [
          [1, 2],
          [4, 5],
          [6],
        ]);
      });
    });

    test('should take an asynchronous onFlush in either form', () {
      fakeAsync((async) {
        final flushes = <List<String>>[];

        Future<void> markAllRead(List<String> ids) async => flushes.add(ids);

        final fromExtension = markAllRead.buffered(32.toDuration());
        final fromLambda = buffer<String>(markAllRead, 32.toDuration());

        fromExtension('a');
        fromLambda('b');
        async.elapse(32.toDuration());

        expect(flushes, [
          ['a'],
          ['b'],
        ]);
      });
    });
  });
}

// Yields [count] values and then fails, the way a lazy source backed by a
// stream or a database cursor can.
Iterable<int> _failsAfter(int count) sync* {
  for (var i = 0; i < count; i++) {
    yield i;
  }
  throw StateError('iteration failed');
}
