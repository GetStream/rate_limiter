import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

// `elapse` advances the clock and runs timers as they come due;
// `elapseBlocking` advances it without running them, as a tight loop would.
void main() {
  group('debounce', () {
    test('should debounce a function', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, 32.toDuration());

        var results = [
          debounced(['a']),
          debounced(['b']),
          debounced(['c'])
        ];

        expect(results, [null, null, null]);
        expect(callCount, 0);

        async.elapse(128.toDuration());
        expect(callCount, 1);

        results = [
          debounced(['d']),
          debounced(['e']),
          debounced(['f'])
        ];

        expect(results, ['c', 'c', 'c']);
        expect(callCount, 1);

        async.elapse(256.toDuration());
        expect(callCount, 2);
      });
    });

    test('should cancel all the remaining delayed functions', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, 32.toDuration());

        final results = [
          debounced(['a']),
          debounced(['b']),
          debounced(['c'])
        ];

        async.elapse(30.toDuration());

        debounced.cancel();

        expect(results, [null, null, null]);
        expect(callCount, 0);

        // Past the trailing call's deadline, so `cancel` is what stopped it.
        async.elapse(128.toDuration());
        expect(callCount, 0);
        expect(debounced.isPending, false);
      });
    });

    test('should immediately invokes all the remaining delayed functions', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, 32.toDuration());

        debounced(['a']);
        debounced(['b']);
        debounced(['c']);

        final result = debounced.flush();

        expect(result, 'c');
        expect(callCount, 1);
      });
    });

    test('should not stay pending after a flush', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, 32.toDuration());

        debounced(['a']);
        async.elapse(10.toDuration());
        debounced(['b']);

        expect(debounced.flush(), 'b');
        expect(debounced.isPending, false);

        // A detached-but-armed timer reschedules itself partway through here.
        for (var elapsed = 0; elapsed < 256; elapsed++) {
          async.elapse(1.toDuration());
          expect(debounced.isPending, false, reason: 'at ${elapsed + 1}ms');
        }
        expect(callCount, 1);
      });
    });

    test('should return if there are functions remaining to get invoked', () {
      fakeAsync((async) {
        final debounced = debounce(identity, 32.toDuration());

        debounced(['a']);

        expect(debounced.isPending, true);

        async.elapse(32.toDuration());

        expect(debounced.isPending, false);
      });
    });

    test('subsequent debounced calls return the last `func` result', () {
      fakeAsync((async) {
        final debounced = debounce(identity, 32.toDuration());
        debounced(['a']);

        async.elapse(64.toDuration());
        expect(debounced(['b']), 'a');

        async.elapse(128.toDuration());
        expect(debounced(['c']), 'b');
      });
    });

    test('should not immediately call `func` when `wait` is `0`', () {
      fakeAsync((async) {
        var callCount = 0;
        final debounced = debounce(() {
          ++callCount;
        }, Duration.zero);

        debounced();
        debounced();
        expect(callCount, 0);

        async.elapse(Duration.zero);
        expect(callCount, 1);
      });
    });

    test('should apply default options', () {
      fakeAsync((async) {
        var callCount = 0;
        final debounced = debounce(() {
          callCount++;
        }, 32.toDuration());

        debounced();
        expect(callCount, 0);

        async.elapse(64.toDuration());
        expect(callCount, 1);
      });
    });

    test('should support a `leading` option', () {
      fakeAsync((async) {
        final callCounts = [0, 0];

        final withLeading = debounce(() {
          callCounts[0]++;
        }, 32.toDuration(), leading: true, trailing: false);

        final withLeadingAndTrailing = debounce(() {
          callCounts[1]++;
        }, 32.toDuration(), leading: true, trailing: true);

        withLeading();
        expect(callCounts[0], 1);

        withLeadingAndTrailing();
        withLeadingAndTrailing();
        expect(callCounts[1], 1);

        async.elapse(64.toDuration());
        expect(callCounts, [1, 2]);

        withLeading();
        expect(callCounts[0], 2);
      });
    });

    test('subsequent leading debounced calls return the last `func` result',
        () {
      fakeAsync((async) {
        final debounced = debounce(
          identity,
          32.toDuration(),
          leading: true,
          trailing: false,
        );

        var results = [
          debounced(['a']),
          debounced(['b'])
        ];

        expect(results, ['a', 'a']);

        async.elapse(64.toDuration());
        results = [
          debounced(['c']),
          debounced(['d'])
        ];
        expect(results, ['c', 'c']);
      });
    });

    test('should support a `trailing` option', () {
      fakeAsync((async) {
        var withCount = 0;
        var withoutCount = 0;

        final withTrailing = debounce(() {
          withCount++;
        }, 32.toDuration(), trailing: true);

        final withoutTrailing = debounce(() {
          withoutCount++;
        }, 32.toDuration(), trailing: false);

        withTrailing();
        expect(withCount, 0);

        withoutTrailing();
        expect(withoutCount, 0);

        async.elapse(64.toDuration());
        expect(withCount, 1);
        expect(withoutCount, 0);
      });
    });

    test('should support a `maxWait` option', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(() {
          ++callCount;
        }, 32.toDuration(), maxWait: 64.toDuration());

        debounced();
        debounced();
        expect(callCount, 0);

        async.elapse(128.toDuration());
        expect(callCount, 1);
        debounced();
        debounced();
        expect(callCount, 1);

        async.elapse(256.toDuration());
        expect(callCount, 2);
      });
    });

    test('should support `maxWait` in a tight loop', () {
      fakeAsync((async) {
        const limit = 320;
        var withCount = 0;
        var withoutCount = 0;

        final withMaxWait = debounce(() {
          withCount++;
        }, 64.toDuration(), maxWait: 128.toDuration());

        final withoutMaxWait = debounce(() {
          withoutCount++;
        }, 96.toDuration());

        // No timer can run in a tight loop, so only `maxWait` breaks out.
        for (var elapsed = 0; elapsed < limit; elapsed++) {
          withMaxWait();
          withoutMaxWait();
          async.elapseBlocking(1.toDuration());
        }

        expect(withoutCount, 0);
        expect(withCount, greaterThan(0));

        async.elapse(1.toDuration());
        expect(withoutCount, 0);
      });
    });

    test(
        'should queue a trailing call for subsequent debounced calls after '
        '`maxWait`', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(() {
          ++callCount;
        }, 200.toDuration(), maxWait: 200.toDuration());

        debounced();

        async.elapse(190.toDuration());
        debounced();
        async.elapse(200.toDuration());
        debounced();
        async.elapse(210.toDuration());
        debounced();

        async.elapse(500.toDuration());
        expect(callCount, 3);
      });
    });

    test('should cancel `maxDelayed` when `delayed` is invoked', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(() {
          callCount++;
        }, 32.toDuration(), maxWait: 64.toDuration());

        debounced();

        async.elapse(128.toDuration());
        debounced();
        expect(callCount, 1);

        async.elapse(192.toDuration());
        expect(callCount, 2);
      });
    });

    test('should invoke the trailing call with the correct arguments', () {
      fakeAsync((async) {
        List<Object?>? actual;
        var callCount = 0;
        final object = <String, Object?>{};

        final debounced = debounce((Map<String, Object?> object, String value) {
          actual = [object, value];
          return ++callCount != 2;
        }, 32.toDuration(), leading: true, maxWait: 64.toDuration());

        // The second invocation is the one `maxWait` forces mid-loop.
        while (debounced([object, 'a']) as bool) {
          async.elapseBlocking(1.toDuration());
        }

        async.elapse(64.toDuration());
        expect(callCount, 2);
        expect(actual, [object, 'a']);
      });
    });
  });

  group('debounce waitBuilder', () {
    test('should wait for the duration the builder returns', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          (String query) => ++callCount,
          100.toDuration(),
          waitBuilder: (args, _) {
            final query = args!.first! as String;
            return query.length <= 2 ? 500.toDuration() : 100.toDuration();
          },
        );

        debounced(['te']);
        async.elapse(499.toDuration());
        expect(callCount, 0);

        async.elapse(1.toDuration());
        expect(callCount, 1);
      });
    });

    test('should re-arm a pending timer when the wait shrinks', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          (int wait) => ++callCount,
          500.toDuration(),
          waitBuilder: (args, _) => (args!.first! as int).toDuration(),
        );

        debounced([500]);
        async.elapse(100.toDuration());
        debounced([200]);

        // Due 200ms after the second call, not 500ms after the first.
        async.elapse(199.toDuration());
        expect(callCount, 0);

        async.elapse(1.toDuration());
        expect(callCount, 1);
      });
    });

    test('should re-arm a pending timer when the wait grows', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          (int wait) => ++callCount,
          100.toDuration(),
          waitBuilder: (args, _) => (args!.first! as int).toDuration(),
        );

        debounced([100]);
        async.elapse(50.toDuration());
        debounced([300]);

        async.elapse(299.toDuration());
        expect(callCount, 0);

        async.elapse(1.toDuration());
        expect(callCount, 1);
      });
    });

    test('should pass named arguments to the builder', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          ({required int ms}) => ++callCount,
          100.toDuration(),
          waitBuilder: (_, namedArgs) => (namedArgs![#ms]! as int).toDuration(),
        );

        debounced(null, {#ms: 250});
        async.elapse(249.toDuration());
        expect(callCount, 0);

        async.elapse(1.toDuration());
        expect(callCount, 1);
      });
    });

    test('should keep honouring maxWait', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          (int wait) => ++callCount,
          50.toDuration(),
          maxWait: 200.toDuration(),
          waitBuilder: (args, _) => (args!.first! as int).toDuration(),
        );

        // Each call pushes the wait out, so only maxWait can fire it.
        for (var elapsed = 0; elapsed < 400; elapsed += 40) {
          debounced([300]);
          async.elapse(40.toDuration());
        }

        expect(callCount, greaterThan(0));
      });
    });
  });
}
