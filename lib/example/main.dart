import 'package:rate_limit/rate_limit.dart';

void main() {
  var count = 0;

  // updates the count value by one and prints it
  void regularFunction() {
    count += 1;
    print(count);
  }

  // regularFunction get's executed 1000000 times
  for (var i = 0; i < 1000000; i++) {
    regularFunction();
  }

  // delays invoking `func` until after 100 milliseconds have elapsed
  // since the last time the debounced function was invoked
  final debouncedFunction = regularFunction.debounced(
    const Duration(milliseconds: 100),
  );

  // debouncedFunction get's executed only once even though invoked
  // 1000000 times
  for (var i = 0; i < 1000000; i++) {
    debouncedFunction();
  }

  // only invokes `func` at most once per every 100 milliseconds
  final throttledFunction = regularFunction.throttled(
    const Duration(milliseconds: 100),
  );

  // throttledFunction get's executed ~3 times even though invoked
  // 1000000 times
  for (var i = 0; i < 1000000; i++) {
    throttledFunction();
  }
}
