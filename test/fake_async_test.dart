import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

// `Debounce` reads the time through `package:clock`, so `fakeAsync` controls
// both its timers and its clock. These tests run instantly, without any real
// waiting.
void main() {
  group('debounce with a fake clock', () {
    test('should invoke on the trailing edge once the wait elapses', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce((String value) {
          ++callCount;
          return value;
        }, const Duration(milliseconds: 32));

        final results = [
          debounced(['a']),
          debounced(['b']),
          debounced(['c'])
        ];

        expect(results, [null, null, null]);
        expect(callCount, 0);

        async.elapse(const Duration(milliseconds: 128));

        expect(callCount, 1);
        expect(debounced(['d']), 'c');
      });
    });

    test('should honour maxWait', () {
      fakeAsync((async) {
        var callCount = 0;

        final debounced = debounce(
          () => ++callCount,
          const Duration(milliseconds: 32),
          maxWait: const Duration(milliseconds: 64),
        );

        // Keep calling within the wait window so only `maxWait` can fire it.
        for (var i = 0; i < 8; i++) {
          debounced();
          async.elapse(const Duration(milliseconds: 16));
        }

        expect(callCount, 2);
      });
    });
  });

  group('throttle with a fake clock', () {
    test('should invoke at most once per wait', () {
      fakeAsync((async) {
        var callCount = 0;

        final throttled = throttle(() => ++callCount, 32.toDuration());

        throttled();
        throttled();
        throttled();

        // Leading edge fired immediately.
        expect(callCount, 1);

        async.elapse(const Duration(milliseconds: 64));

        // Trailing edge fired once for the calls made during the wait.
        expect(callCount, 2);
      });
    });
  });
}
