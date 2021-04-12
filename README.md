
# Rate Limiter

<img src="https://user-images.githubusercontent.com/25670178/114412456-bc502480-9bca-11eb-8b7c-db69fa389a59.png?sanitize=true">

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=102)](https://opensource.org/licenses/MIT) [![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/GetStream/rate_limit/blob/master/LICENSE) [![CodeCov](https://codecov.io/gh/GetStream/rate_limiter/branch/master/graph/badge.svg)](https://codecov.io/gh/GetStream/rate_limiter) [![Version](https://img.shields.io/pub/v/rate_limiter.svg)](https://pub.dartlang.org/packages/rate_limiter)

**[** Built with ♥ at [<strong>Stream</strong>](https://getstream.io/) **]**

## Introduction
_Rate limiting_ is a strategy for limiting an action. It puts a cap on how often someone can repeat an action within a certain timeframe. Using `rate_limiter` we made it easier than ever to apply these strategies on regular dart functions.

## Index
- [Installation](#installation)
- [Strategies](#strategies)
	- [Debounce](#debounce)
	- [Throttle](#throttle)
- [IsPending](#is-pending)
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
  const Duration(milliseconds: 350),
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

### IsPending
Used to check if the there are functions still remaining to get invoked.
```dart
final pending = debouncedFunction.isPending;
final pending = throttledFunction.isPending;
```

### Flush
Used to immediately invoke all the remaining delayed functions.
```dart
final result = debouncedFunction.flush();
final result = throttledFunction.flush();
```

### Cancellation
Used to cancel all the remaining delayed functions.
```dart
debouncedFunction.cancel();  
throttledFunction.cancel();
```
