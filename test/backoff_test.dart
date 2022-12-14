import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  test('backOff (success)', () async {
    var count = 0;
    final f = backOff(() {
      count++;
      return true;
    });
    expect(f, completion(isTrue));
    expect(count, equals(1));
  });

  test('retry (unhandled exception)', () async {
    var count = 0;
    final f = backOff(
      () {
        count++;
        throw Exception('Retry will fail');
      },
      maxAttempts: 5,
      retryIf: (_, __) => false,
    );
    await expectLater(f, throwsA(isException));
    expect(count, equals(1));
  });

  test('retry (retryIf, exhaust retries)', () async {
    var count = 0;
    final f = backOff(
      () {
        count++;
        throw FormatException('Retry will fail');
      },
      maxAttempts: 5,
      maxDelay: Duration(),
      retryIf: (e, _) => e is FormatException,
    );
    await expectLater(f, throwsA(isFormatException));
    expect(count, equals(5));
  });

  test('retry (success after 2)', () async {
    var count = 0;
    final f = backOff(
      () {
        count++;
        if (count == 1) {
          throw FormatException('Retry will be okay');
        }
        return true;
      },
      maxAttempts: 5,
      maxDelay: Duration(),
      retryIf: (e, _) => e is FormatException,
    );
    await expectLater(f, completion(isTrue));
    expect(count, equals(2));
  });

  test('retry (no retryIf)', () async {
    var count = 0;
    final f = backOff(
      () {
        count++;
        if (count == 1) {
          throw FormatException('Retry will be okay');
        }
        return true;
      },
      maxAttempts: 5,
      maxDelay: Duration(),
    );
    await expectLater(f, completion(isTrue));
    expect(count, equals(2));
  });

  test('retry (unhandled on 2nd try)', () async {
    var count = 0;
    final f = backOff(
      () {
        count++;
        if (count == 1) {
          throw FormatException('Retry will be okay');
        }
        throw Exception('unhandled thing');
      },
      maxAttempts: 5,
      maxDelay: Duration(),
      retryIf: (e, _) => e is FormatException,
    );
    await expectLater(f, throwsA(isException));
    expect(count, equals(2));
  });
}
