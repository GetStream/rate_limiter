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
}
