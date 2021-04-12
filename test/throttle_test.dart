import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';
import 'utils.dart';

void main() {
  group('throttle', () {
    test('should throttle a function', () async {
      var callCount = 0;
      final throttled = throttle(() {
        callCount++;
      }, 32.toDuration());

      throttled();
      throttled();
      throttled();

      var lastCount = callCount;
      expect(callCount.toBool(), isTrue);

      await delay(64);
      expect(callCount > lastCount, isTrue);
    });

    test('should cancel all the remaining delayed functions', () async {
      var callCount = 0;

      final throttled = throttle((String value) {
        ++callCount;
        return value;
      }, const Duration(milliseconds: 32), leading: false);

      var results = [
        throttled(['a']),
        throttled(['b']),
        throttled(['c'])
      ];

      await delay(30);

      throttled.cancel();

      expect(results, [null, null, null]);
      expect(callCount, 0);
    });

    test(
      'should immediately invokes all the remaining delayed functions',
      () async {
        var callCount = 0;

        final throttled = throttle((String value) {
          ++callCount;
          return value;
        }, const Duration(milliseconds: 32), leading: false);

        throttled(['a']);
        throttled(['b']);
        throttled(['c']);

        final result = throttled.flush();

        expect(result, 'c');
        expect(callCount, 1);
      },
    );

    test(
      'should return if there are functions remaining to get invoked',
      () async {
        final throttled = throttle(identity, const Duration(milliseconds: 32));

        throttled(['a']);

        expect(throttled.isPending, true);

        await delay(32);

        expect(throttled.isPending, false);
      },
    );

    test(
      'subsequent calls should return the result of the first call',
      () async {
        final throttled = throttle(identity, 32.toDuration());
        var results = [
          throttled(['a']),
          throttled(['b'])
        ];

        expect(results, ['a', 'a']);

        await delay(64);
        results = [
          throttled(['c']),
          throttled(['d'])
        ];

        expect(results[0], isNot('a'));
        expect(results[0], isNotNull);

        expect(results[1], isNot('d'));
        expect(results[1], isNotNull);
      },
    );

    test('should not trigger a trailing call when invoked once', () async {
      var callCount = 0;
      final throttled = throttle(() {
        callCount++;
      }, 32.toDuration());

      throttled();
      expect(callCount, 1);

      await delay(64);
      expect(callCount, 1);
    });

    test('should trigger a call when invoked repeatedly', () async {
      var callCount = 0;
      var limit = 320;
      final throttled = throttle(() {
        callCount++;
      }, 32.toDuration());

      var start = DateTime.now().millisecondsSinceEpoch;
      while ((DateTime.now().millisecondsSinceEpoch - start) < limit) {
        throttled();
      }
      var actual = callCount > 1;

      await delay(1);
      expect(actual, isTrue);
    });

    test(
      'should trigger a call when invoked repeatedly and `leading` is `false`',
      () async {
        var callCount = 0;
        var limit = 320;
        final throttled = throttle(() {
          callCount++;
        }, 32.toDuration(), leading: false);

        var start = DateTime.now().millisecondsSinceEpoch;
        while ((DateTime.now().millisecondsSinceEpoch - start) < limit) {
          throttled();
        }
        var actual = callCount > 1;

        await delay(1);
        expect(actual, isTrue);
      },
    );

    test('should apply default options', () async {
      var callCount = 0;
      final throttled = throttle(() {
        callCount++;
      }, 32.toDuration());

      throttled();
      throttled();
      expect(callCount, 1);

      await delay(128);
      expect(callCount, 2);
    });

    test('should support a `leading` option', () {
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

    test('should support a `trailing` option', () async {
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

      await delay(256);
      expect(withCount, 2);
      expect(withoutCount, 1);
    });

    test(
      'should not update `lastCalled`, at the end of the timeout, when `trailing` is `false`',
      () async {
        var callCount = 0;

        final throttled = throttle(() {
          callCount++;
        }, 64.toDuration(), trailing: false);

        throttled();
        throttled();

        await delay(96);
        throttled();
        throttled();

        await delay(192);
        expect(callCount > 1, isTrue);
      },
    );
  });
}
