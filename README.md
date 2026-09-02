
# Rate Limiter

<img src="https://user-images.githubusercontent.com/25670178/114412456-bc502480-9bca-11eb-8b7c-db69fa389a59.png?sanitize=true">

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=102)](https://opensource.org/licenses/MIT) [![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/GetStream/rate_limit/blob/master/LICENSE) [![Dart CI](https://github.com/GetStream/rate_limiter/workflows/Dart%20CI/badge.svg)](https://github.com/GetStream/rate_limiter/actions) [![CodeCov](https://codecov.io/gh/GetStream/rate_limiter/branch/master/graph/badge.svg)](https://codecov.io/gh/GetStream/rate_limiter) [![Version](https://img.shields.io/pub/v/rate_limiter.svg)](https://pub.dartlang.org/packages/rate_limiter)

**[** Built with ♥ at [<strong>Stream</strong>](https://getstream.io/) **]**

## Introduction
_Rate limiting_ is a strategy for limiting an action. It puts a cap on how often someone can repeat an action within a certain timeframe. Using `rate_limiter` we made it easier than ever to apply these strategies on regular dart functions.

( Inspired from [lodash](https://lodash.com/) )

## Index
- [Installation](#installation)
- [Strategies](#strategies)
	- [Debounce](#debounce)
	- [Throttle](#throttle)
    - [BackOff](#backoff)
    - [Buffer](#buffer)
- [Pending](#pending)
- [Flush](#flush)
- [Cancellation](#cancellation)
    
## Installation
Add the following to your  `pubspec.yaml`  and replace  `[version]`  with the latest version:
```yaml
dependencies:
  rate_limiter: ^[version]
```

## Strategies
### Debounce
A _debounced function_ will ignore all calls to it until the calls have stopped for a specified time period. Only then it will call the original function. For instance, if we specify the time as two seconds, and the debounced function is called 10 times with an interval of one second between each call, the function will not call the original function until two seconds after the last (tenth) call.

#### Usage
It's fairly simple to create debounced function with `rate_limiter`

1. Creating from scratch
```dart
final debouncedFunction = debounce((String value) {  
  print('Got value : $value');  
  return value;  
}, const Duration(seconds: 2));
```
2. Converting an existing function into debounced function
```dart
String regularFunction(String value) {  
  print('Got value : $value');  
  return value;  
}  
  
final debouncedFunction = regularFunction.debounced(  
  const Duration(seconds: 2),  
);
```

#### Example
Often times, search boxes offer dropdowns that provide autocomplete options for the user’s current input. Sometimes the items suggested are fetched from the backend via API (for instance, on Google Maps). The autocomplete API gets called whenever the search query changes. Without debounce, an API call would be made for every letter you type, even if you’re typing very fast. Debouncing by one second will ensure that the autocomplete function does nothing until one second after the user is done typing.
```dart
final debouncedAutocompleteSearch = debounce(
  (String searchQuery) async {
    // fetches results from the api
    final results = await searchApi.get(searchQuery);
    // updates suggestion list
    updateSearchSuggestions(results);
  },
  const Duration(seconds: 1),
);

TextField(
  onChanged: (query) {
    debouncedAutocompleteSearch([query]);
  },
);
```

### Throttle
To _throttle_ a function means to ensure that the function is called at most once in a specified time period (for instance, once every 10 seconds). This means throttling will prevent a function from running if it has run “recently”. Throttling also ensures a function is run regularly at a fixed rate.

#### Usage
Creating throttled function is similar to debounce function

1. Creating from scratch
```dart
final throttledFunction = throttle((String value) {  
  print('Got value : $value');  
  return value;  
}, const Duration(seconds: 2));
```
2. Converting an existing function into throttled function
```dart
String regularFunction(String value) {  
  print('Got value : $value');  
  return value;  
}  
  
final throttledFunction = regularFunction.throttled(  
  const Duration(seconds: 2),  
);
```

#### Example
In action games, the user often performs a key action by pushing a button (example: shooting, punching). But, as any gamer knows, users often press the buttons much more than is necessary, probably due to the excitement and intensity of the action. So the user might hit “Punch” 10 times in 5 seconds, but the game character can only throw one punch in one second. In such a situation, it makes sense to throttle the action. In this case, throttling the “Punch” action to one second would ignore the second button press each second.

```dart
final throttledPerformPunch = throttle(
  () {
    print('Performed one punch to the opponent');
  },
  const Duration(seconds: 1),
);

RaisedButton(
  onPressed: (){
    throttledPerformPunch();
  }
  child: Text('Punch')
);
```

### BackOff
BackOff is a strategy that allows you to retry a function call multiple times with a delay between each call. It is useful when you want to retry a function call multiple times in case of failure.

#### Usage
Creating backoff function is similar to debounce and throttle function.

1. Creating from scratch
```dart
final response = backOff(
  // Make a GET request
  () => http.get('https://google.com').timeout(Duration(seconds: 5)),
  maxAttempts: 5,
  maxDelay: Duration(seconds: 5),
  // Retry on SocketException or TimeoutException
  retryIf: (e, _) => e is SocketException || e is TimeoutException,
);
```
2. Converting an existing function into backoff function
```dart
Future<String> regularFunction() async {  
  // Make a GET request
  final response = await http.get('https://google.com').timeout(Duration(seconds: 5));
  return response.body;
}

final response = regularFunction.backOff(
  maxAttempts: 5,
  maxDelay: Duration(seconds: 5),
  // Retry on SocketException or TimeoutException
  retryIf: (e, _) => e is SocketException || e is TimeoutException,
);
```

#### Example
While making a network request, it is possible that the request fails due to network issues. In such cases, it is useful to retry the request multiple times with a delay between each call. This is where backoff strategy comes in handy.

```dart
final response = backOff(
  // Make a GET request
  () => http.get('https://google.com').timeout(Duration(seconds: 5)),
  maxAttempts: 5,
  maxDelay: Duration(seconds: 5),
  // Retry on SocketException or TimeoutException
  retryIf: (e, _) => e is SocketException || e is TimeoutException,
);
```

### Buffer
A _buffered function_ collects the items passed to it and invokes your function **once** with all of them, rather than once per item. Where debounce and throttle keep only the last call's arguments and drop the rest, a buffer keeps every one — so it batches work instead of shedding it.

The buffer is flushed once `wait` has passed since the first item landed in it, or as soon as it holds `maxSize` items, whichever comes first. Only one flush runs at a time: while your function is working, arriving items collect for the next one, which goes out once it has come due *and* the running one has finished — whichever is later. By default nothing is dropped and no call ever waits on a flush already running — pass `maxQueueSize` to cap the buffer and shed the excess instead. A call that reaches `maxSize` hands its batch over itself, so synchronous work in your function runs before that call returns.

#### Usage
1. Creating from scratch
```dart
final markRead = buffer<String>((ids) {
  print('Marking ${ids.length} messages read');
  return api.markAllRead(ids);
}, const Duration(milliseconds: 500), maxSize: 25);
```
2. Converting an existing function into a buffered function
```dart
Future<void> markAllRead(List<String> ids) => api.markAllRead(ids);

final markRead = markAllRead.buffered(
  const Duration(milliseconds: 500),
  maxSize: 25,
);
```

#### Example
Marking messages read as the user scrolls calls `markRead` once per message. Debouncing it would send only the last id and lose the other nineteen; buffering sends one request carrying all twenty.
```dart
void onMessageSeen(String id) {
  markRead(id);
}
```

Passing `Duration.zero` batches everything queued up in the current event loop turn, which is how a data loader collapses a screen's worth of lookups into one request.
```dart
final loadUsers = buffer<String>(
  (ids) => api.getUsers(ids),
  Duration.zero,
);
```

A producer faster than `onFlush` can grow the buffer without bound. `maxQueueSize` caps it, `overflow` picks which end goes, and `onDrop` reports what that cost.
```dart
final trackEvent = buffer<Event>(
  (events) => analytics.send(events),
  const Duration(seconds: 5),
  maxQueueSize: 10000,
  overflow: OverflowPolicy.dropOldest, // or dropNewest, to keep what is waiting
  onDrop: (events) => log.warning('dropped ${events.length} events'),
);
```

The two caps work on different things and compose: `maxSize` limits what any one flush carries, `maxQueueSize` limits the backlog that builds up behind a flush still running.

Because no caller is waiting on a scheduled flush, failures go to `onError` instead — which is also handed the items, so they can be re-queued rather than lost.
```dart
final markRead = buffer<String>(
  (ids) => api.markAllRead(ids),
  const Duration(milliseconds: 500),
  onError: (error, stackTrace, ids) => retryQueue.addAll(ids),
);
```

Handing them back to the buffer retries them on the next flush:
```dart
late final markRead = buffer<String>(
  (ids) => api.markAllRead(ids),
  const Duration(milliseconds: 500),
  onError: (error, stackTrace, ids) => markRead.addAll(ids),
);
```
Retried items go to the back of the buffer, so their order is not preserved, and nothing spaces the attempts out. For that, put [backOff](#backoff) inside the flush instead:
```dart
final markRead = buffer<String>(
  (ids) => backOff(
    () => api.markAllRead(ids),
    maxAttempts: 4,
    retryIf: (error, attempt) => error is SocketException,
  ),
  const Duration(milliseconds: 500),
  // Reached only once backoff has run out of attempts.
  onError: (error, stackTrace, ids) => log.warning('gave up on ${ids.length}'),
);
```
Every attempt re-sends the same batch, `onError` fires once at the end rather than per attempt, and `await markRead.flush()` waits the retries out. Pick one of the two though — requeuing through `onError` *and* retrying with `backOff` compounds the two schedules.

### Pending
Used to check if the there are functions still remaining to get invoked.
```dart
final pending = debouncedFunction.isPending;
final pending = throttledFunction.isPending;
final pending = bufferedFunction.isPending;
```

### Flush
Used to immediately invoke all the remaining delayed functions.
```dart
final result = debouncedFunction.flush();
final result = throttledFunction.flush();
// A buffer's flush covers the items it holds right now, and completes once
// your function does, so it can be awaited before going away.
await bufferedFunction.flush();
```

### Cancellation
Used to cancel all the remaining delayed functions.
```dart
debouncedFunction.cancel();  
throttledFunction.cancel();
// Discards the items collected so far, without invoking your function.
bufferedFunction.cancel();
```
