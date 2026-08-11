import 'package:test/test.dart';
import 'package:rate_limiter/rate_limiter.dart';

void main() {
  test('should convert regular function into a debounce function', () {
    String regularFunction(String value) {
      return value;
    }

    final debounced = regularFunction.debounced(const Duration(seconds: 3));
    expect(debounced, isA<Debounce>());
  });

  test('should convert regular function into a throttle function', () {
    String regularFunction(String value) {
      return value;
    }

    final throttled = regularFunction.throttled(const Duration(seconds: 3));
    expect(throttled, isA<Throttle>());
  });

  test('should convert regular function into a backOff function', () async {
    var callCount = 0;

    Future<String> regularFunction() async {
      ++callCount;
      return 'value';
    }

    // Succeeds on the first attempt, so no retry delay is incurred.
    final result = await regularFunction.backOff();

    expect(result, 'value');
    expect(callCount, 1);
  });

  test('should forward the options to the backOff function', () async {
    var callCount = 0;

    Future<String> regularFunction() async {
      ++callCount;
      throw Exception('failed');
    }

    await expectLater(
      regularFunction.backOff(
        delayFactor: Duration.zero,
        maxAttempts: 2,
        retry: (_, __) => true,
      ),
      throwsException,
    );
    expect(callCount, 2);
  });
}
