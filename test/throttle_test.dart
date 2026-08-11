import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

// `Throttle` delegates to `Debounce`, so like the debounce suite these run
// against a clock `fakeAsync` controls rather than real elapsed time. See
// `debounce_test.dart` for the difference between `elapse` and `elapseBlocking`.
void main() {
  group('throttle', () {
    test('should throttle a function', () {
      fakeAsync((async) {
        var callCount = 0;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration());

        throttled();
        throttled();
        throttled();

        // The leading edge fires immediately, the other two are collapsed.
        expect(callCount, 1);

        async.elapse(64.toDuration());
        // ...and the collapsed calls produce a single trailing invocation.
        expect(callCount, 2);
      });
    });

    test('should cancel all the remaining delayed functions', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle((String value) {
          ++callCount;
          return value;
        }, 32.toDuration(), leading: false);

        final results = [
          throttled(['a']),
          throttled(['b']),
          throttled(['c'])
        ];

        async.elapse(30.toDuration());

        throttled.cancel();

        expect(results, [null, null, null]);
        expect(callCount, 0);

        // Past the point the trailing call would have fired, to prove `cancel`
        // actually dropped it rather than the test finishing first.
        async.elapse(128.toDuration());
        expect(callCount, 0);
        expect(throttled.isPending, false);
      });
    });

    test('should immediately invokes all the remaining delayed functions', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle((String value) {
          ++callCount;
          return value;
        }, 32.toDuration(), leading: false);

        throttled(['a']);
        throttled(['b']);
        throttled(['c']);

        final result = throttled.flush();

        expect(result, 'c');
        expect(callCount, 1);
      });
    });

    test('should not stay pending after a flush', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle((String value) {
          ++callCount;
          return value;
        }, 32.toDuration(), leading: false);

        throttled(['a']);
        async.elapse(10.toDuration());
        throttled(['b']);

        expect(throttled.flush(), 'b');
        expect(throttled.isPending, false);

        for (var elapsed = 0; elapsed < 256; elapsed++) {
          async.elapse(1.toDuration());
          expect(throttled.isPending, false, reason: 'at ${elapsed + 1}ms');
        }
        expect(callCount, 1);
      });
    });

    test('should return if there are functions remaining to get invoked', () {
      fakeAsync((async) {
        final throttled = throttle(identity, 32.toDuration());

        throttled(['a']);

        expect(throttled.isPending, true);

        async.elapse(32.toDuration());

        expect(throttled.isPending, false);
      });
    });

    test('subsequent calls should return the result of the first call', () {
      fakeAsync((async) {
        final throttled = throttle(identity, 32.toDuration());
        var results = [
          throttled(['a']),
          throttled(['b'])
        ];

        expect(results, ['a', 'a']);

        async.elapse(64.toDuration());
        results = [
          throttled(['c']),
          throttled(['d'])
        ];

        // A new leading edge, so `'c'` is invoked and `'d'` collapses into it.
        expect(results, ['c', 'c']);
      });
    });

    test('should not trigger a trailing call when invoked once', () {
      fakeAsync((async) {
        var callCount = 0;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration());

        throttled();
        expect(callCount, 1);

        async.elapse(64.toDuration());
        expect(callCount, 1);
      });
    });

    test('should trigger a call when invoked repeatedly', () {
      fakeAsync((async) {
        var callCount = 0;
        const limit = 320;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration());

        for (var elapsed = 0; elapsed < limit; elapsed++) {
          throttled();
          async.elapseBlocking(1.toDuration());
        }

        // A tight loop starves the timers, so every invocation past the leading
        // edge has to come from `maxWait`, which `Throttle` sets to `wait`.
        expect(callCount, greaterThan(1));
      });
    });

    test(
        'should trigger a call when invoked repeatedly and `leading` is '
        '`false`', () {
      fakeAsync((async) {
        var callCount = 0;
        const limit = 320;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration(), leading: false);

        for (var elapsed = 0; elapsed < limit; elapsed++) {
          throttled();
          async.elapseBlocking(1.toDuration());
        }

        expect(callCount, greaterThan(1));
      });
    });

    test('should apply default options', () {
      fakeAsync((async) {
        var callCount = 0;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration());

        throttled();
        throttled();
        expect(callCount, 1);

        async.elapse(128.toDuration());
        expect(callCount, 2);
      });
    });

    test('should support a `leading` option', () {
      fakeAsync((async) {
        final withLeading = throttle(
          identity,
          32.toDuration(),
          leading: true,
        );
        expect(withLeading(['a']), 'a');

        final withoutLeading = throttle(
          identity,
          32.toDuration(),
          leading: false,
        );
        expect(withoutLeading(['a']), isNull);
      });
    });

    test('should support a `trailing` option', () {
      fakeAsync((async) {
        var withCount = 0;
        var withoutCount = 0;

        final withTrailing = throttle((value) {
          withCount++;
          return value;
        }, 64.toDuration(), trailing: true);

        final withoutTrailing = throttle((value) {
          withoutCount++;
          return value;
        }, 64.toDuration(), trailing: false);

        expect(withTrailing(['a']), 'a');
        expect(withTrailing(['b']), 'a');

        expect(withoutTrailing(['a']), 'a');
        expect(withoutTrailing(['b']), 'a');

        async.elapse(256.toDuration());
        // The trailing-enabled one picks up the collapsed `'b'` call.
        expect(withCount, 2);
        expect(withoutCount, 1);
      });
    });

    test(
        'should not update `lastCalled`, at the end of the timeout, when '
        '`trailing` is `false`', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle(() {
          callCount++;
        }, 64.toDuration(), trailing: false);

        throttled();
        throttled();

        async.elapse(96.toDuration());
        throttled();
        throttled();

        async.elapse(192.toDuration());
        expect(callCount, greaterThan(1));
      });
    });
  });
}
