// Identity function
T identity<T>(T value) => value;

// Extension function to convert int into durations
extension IntX on int {
  Duration toDuration() => Duration(milliseconds: this);
}
