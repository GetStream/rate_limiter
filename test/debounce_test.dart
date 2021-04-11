import 'package:rate_limit/rate_limit.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('debounce', () {
    test('should debounce a function', () async {
      var callCount = 0;

      final debounced = debounce((String value) {
        ++callCount;
        return value;
      }, const Duration(milliseconds: 32));

      var results = [
        debounced(['a']),
        debounced(['b']),
        debounced(['c'])
      ];

      expect(results, [null, null, null]);
      expect(callCount, 0);

      await delay(128);

      results = [
        debounced(['d']),
        debounced(['e']),
        debounced(['f'])
      ];

      expect(results, ['c', 'c', 'c']);
      expect(callCount, 1);

      await delay(256);

      expect(callCount, 2);
    });

    test('should cancel all the remaining delayed functions', () async {
      var callCount = 0;

      final debounced = debounce((String value) {
        ++callCount;
        return value;
      }, const Duration(milliseconds: 32));

      var results = [
        debounced(['a']),
        debounced(['b']),
        debounced(['c'])
      ];

      await delay(30);

      debounced.cancel();

      expect(results, [null, null, null]);
      expect(callCount, 0);
    });

    test(
      'should immediately invokes all the remaining delayed functions',
      () async {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, const Duration(milliseconds: 32));

        debounced(['a']);
        debounced(['b']);
        debounced(['c']);

        final result = debounced.flush();

        expect(result, 'c');
        expect(callCount, 1);
      },
    );

    test(
      'should return if there are functions remaining to get invoked',
      () async {
        final debounced = debounce(identity, const Duration(milliseconds: 32));

        debounced(['a']);

        expect(debounced.isPending, true);

        await delay(32);

        expect(debounced.isPending, false);
      },
    );

    test('subsequent debounced calls return the last `func` result', () async {
      final debounced = debounce(identity, 32.toDuration());
      debounced(['a']);

      await delay(64);
      expect(debounced(['b']), isNot('b'));

      await delay(128);
      expect(debounced(['c']), isNot('c'));
    });

    test('should not immediately call `func` when `wait` is `0`', () async {
      var callCount = 0;
      final debounced = debounce(() {
        ++callCount;
      }, Duration.zero);

      debounced();
      debounced();
      expect(callCount, 0);

      await delay(5);
      expect(callCount, 1);
    });

    test('should apply default options', () async {
      var callCount = 0;
      final debounced = debounce(() {
        callCount++;
      }, 32.toDuration());

      debounced();
      expect(callCount, 0);

      await delay(64);
      expect(callCount, 1);
    });

    test('should support a `leading` option', () async {
      var callCounts = [0, 0];

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

      await delay(64);
      expect(callCounts, [1, 2]);

      withLeading();
      expect(callCounts[0], 2);
    });

    test(
      'subsequent leading debounced calls return the last `func` result',
      () async {
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

        await delay(64);
        results = [
          debounced(['c']),
          debounced(['d'])
        ];
        expect(results, ['c', 'c']);
      },
    );

    test('should support a `trailing` option', () async {
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

      await delay(64);
      expect(withCount, 1);
      expect(withoutCount, 0);
    });

    test('should support a `maxWait` option', () async {
      var callCount = 0;

      final debounced = debounce(() {
        ++callCount;
      }, 32.toDuration(), maxWait: 64.toDuration());

      debounced();
      debounced();
      expect(callCount, 0);

      await delay(128);
      expect(callCount, 1);
      debounced();
      debounced();
      expect(callCount, 1);

      await delay(256);
      expect(callCount, 2);
    });

    test('should support `maxWait` in a tight loop', () async {
      var limit = 320;
      var withCount = 0;
      var withoutCount = 0;

      final withMaxWait = debounce(() {
        withCount++;
      }, 64.toDuration(), maxWait: 128.toDuration());

      final withoutMaxWait = debounce(() {
        withoutCount++;
      }, 96.toDuration());

      var start = DateTime.now().millisecondsSinceEpoch;
      while ((DateTime.now().millisecondsSinceEpoch - start) < limit) {
        withMaxWait();
        withoutMaxWait();
      }
      var actual = [withoutCount.toBool(), withCount.toBool()];

      await delay(1);
      expect(actual, [false, true]);
    });

    test(
      'should queue a trailing call for subsequent debounced calls after `maxWait`',
      () async {
        var callCount = 0;

        var debounced = debounce(() {
          ++callCount;
        }, 200.toDuration(), maxWait: 200.toDuration());

        debounced();

        await delay(190);
        debounced();
        await delay(200);
        debounced();
        await delay(210);
        debounced();

        await delay(500);
        expect(callCount, 3);
      },
    );

    test('should cancel `maxDelayed` when `delayed` is invoked', () async {
      var callCount = 0;

      final debounced = debounce(() {
        callCount++;
      }, 32.toDuration(), maxWait: 64.toDuration());

      debounced();

      await delay(128);
      debounced();
      expect(callCount, 1);

      await delay(192);
      expect(callCount, 2);
    });

    test(
      'should invoke the trailing call with the correct arguments',
      () async {
        var actual;
        var callCount = 0;
        var object = {};

        final debounced = debounce((Map object, String value) {
          actual = [object, value];
          return ++callCount != 2;
        }, 32.toDuration(), leading: true, maxWait: 64.toDuration());

        while (true) {
          if (!(debounced([object, 'a']) as bool)) {
            break;
          }
        }

        await delay(64);
        expect(callCount, 2);
        expect(actual, [object, 'a']);
      },
    );
  });
}
