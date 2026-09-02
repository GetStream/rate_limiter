import 'package:fake_async/fake_async.dart';
import 'package:rate_limiter/rate_limiter.dart';
import 'package:test/test.dart';

import 'utils.dart';

class _Unreachable implements Exception {}

class _Rejected implements Exception {}

void main() {
  group('buffer with a backed-off flush', () {
    // randomizationFactor is 0 so the retry delays land where the comments say
    // they do: 200ms * 2^attempt, meaning 400ms, then 800ms, then 1600ms.
    Buffer<String> build({
      required Future<void> Function(List<String> ids) send,
      void Function(Object, StackTrace, List<String>)? onError,
      int maxAttempts = 4,
    }) {
      return buffer<String>(
        (ids) => backOff(
          () => send(ids),
          maxAttempts: maxAttempts,
          delayFactor: 200.toDuration(),
          randomizationFactor: 0,
          retryIf: (error, attempt) => error is _Unreachable,
        ),
        500.toDuration(),
        onError: onError,
      );
    }

    test('should retry the whole batch without telling onError', () {
      fakeAsync((async) {
        final attempts = <List<String>>[];
        Object? reported;

        final markRead = build(
          send: (ids) async {
            attempts.add(ids);
            if (attempts.length == 1) throw _Unreachable();
          },
          onError: (e, s, ids) => reported = e,
        );

        markRead('a');
        markRead('b');

        async.elapse(500.toDuration());
        expect(attempts, [
          ['a', 'b'],
        ]);

        async.elapse(400.toDuration());
        expect(
            attempts,
            [
              ['a', 'b'],
              ['a', 'b'],
            ],
            reason: 'the same batch went out again, intact');
        expect(reported, isNull, reason: 'it succeeded, so nobody was told');
      });
    });

    test('should hand the items to onError only once backoff gives up', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? reported;
        List<String>? handedBack;

        final markRead = build(
          maxAttempts: 3,
          send: (ids) async {
            attempts++;
            throw _Unreachable();
          },
          onError: (e, s, ids) {
            reported = e;
            handedBack = ids;
          },
        );

        markRead('a');

        async.elapse(500.toDuration());
        expect(reported, isNull, reason: 'still retrying');

        async.elapse(1200.toDuration());
        expect(attempts, 3);
        expect(reported, isA<_Unreachable>());
        expect(handedBack, ['a'], reason: 'so they can be re-queued');
      });
    });

    test('should go straight to onError for what retryIf rejects', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? reported;

        final markRead = build(
          send: (ids) async {
            attempts++;
            throw _Rejected();
          },
          onError: (e, s, ids) => reported = e,
        );

        markRead('a');
        async.elapse(500.toDuration());

        expect(attempts, 1);
        expect(reported, isA<_Rejected>());
      });
    });

    test('should hold new items until the retries are done', () {
      fakeAsync((async) {
        final attempts = <List<String>>[];

        final markRead = build(
          send: (ids) async {
            attempts.add(ids);
            if (attempts.length < 3) throw _Unreachable();
          },
          onError: (e, s, ids) {},
        );

        markRead('a');
        async.elapse(500.toDuration()); // attempt one of 'a' fails

        markRead('b');
        async.elapse(500.toDuration()); // 'b' comes due at t=1000, but waits

        expect(
            attempts,
            [
              ['a'],
              ['a'],
            ],
            reason: 'only the retry of a has gone out');

        // The chain runs to t=1700: 400ms then 800ms between its attempts.
        async.elapse(700.toDuration());

        expect(
            attempts,
            [
              ['a'],
              ['a'],
              ['a'],
              ['b'],
            ],
            reason: "'b' went the moment the chain freed the queue");
      });
    });

    test('should keep new items out of a batch being retried', () {
      fakeAsync((async) {
        final attempts = <List<String>>[];

        final markRead = build(
          send: (ids) async {
            attempts.add(ids);
            if (attempts.length == 1) throw _Unreachable();
          },
          onError: (e, s, ids) {},
        );

        markRead('a');
        async.elapse(500.toDuration());

        markRead('b');
        async.elapse(400.toDuration()); // the retry of 'a' lands here

        expect(attempts[1], ['a'],
            reason: "'b' cannot join a batch already handed over");
      });
    });

    test('should let flush wait out the retries', () {
      fakeAsync((async) {
        var attempts = 0;
        var drained = false;

        final markRead = build(
          send: (ids) async {
            attempts++;
            if (attempts == 1) throw _Unreachable();
          },
          onError: (e, s, ids) {},
        );

        markRead('a');
        markRead.flush().then((_) => drained = true).ignore();

        async.flushMicrotasks();
        expect(drained, isFalse, reason: 'the first attempt has failed');

        async.elapse(400.toDuration());

        expect(attempts, 2);
        expect(drained, isTrue, reason: 'flush completed once backoff did');
      });
    });

    test('should report a retry that runs out through flush to its caller', () {
      fakeAsync((async) {
        Object? caught;

        final markRead = build(
          maxAttempts: 2,
          send: (ids) async => throw _Unreachable(),
        );

        markRead('a');
        markRead.flush().then((_) {}, onError: (Object e) {
          caught = e;
        }).ignore();

        async.elapse(400.toDuration());

        expect(caught, isA<_Unreachable>(),
            reason: 'the caller asked, so the caller is told');
      });
    });
  });
}
