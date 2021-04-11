// Identity function
T identity<T>(T value) => value;

// Extension function to convert int into durations
extension IntX on int {
  Duration toDuration() => Duration(milliseconds: this);

  bool toBool() => this == 0 ? false : true;
}

// Top level util function to delay the code execution
Future delay(int milliseconds) =>
    Future.delayed(Duration(milliseconds: milliseconds));
