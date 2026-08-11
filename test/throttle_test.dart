import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

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

        expect(callCount, 1);

        async.elapse(64.toDuration());
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

        // Past the trailing call's deadline, so `cancel` is what stopped it.
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

        // Past the leading edge, only `maxWait` can invoke inside a tight loop.
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

  group('throttle waitBuilder', () {
    test('should throttle at the interval the builder returns', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle(
          (int wait) => ++callCount,
          100.toDuration(),
          waitBuilder: (args, _) => (args!.first! as int).toDuration(),
        );

        throttled([300]);
        expect(callCount, 1);

        throttled([300]);
        async.elapse(299.toDuration());
        expect(callCount, 1);

        async.elapse(1.toDuration());
        expect(callCount, 2);
      });
    });

    test('should keep maxWait pinned to the built wait', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle(
          (int wait) => ++callCount,
          100.toDuration(),
          waitBuilder: (args, _) => (args!.first! as int).toDuration(),
        );

        throttled([100]);

        // A tight loop can only be broken by maxWait. Were maxWait left at the
        // 100ms the throttle was built with, this would invoke half as often.
        for (var elapsed = 0; elapsed < 200; elapsed++) {
          throttled([50]);
          async.elapseBlocking(1.toDuration());
        }

        expect(callCount, greaterThan(2));
      });
    });
  });
}
