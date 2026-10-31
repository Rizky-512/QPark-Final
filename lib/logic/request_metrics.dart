/// Bounded, in-memory diagnostics. Never stores URLs, plates, tokens or bodies.
class RequestMetrics {
  int requests = 0, failures = 0, timeouts = 0;
  String? lastErrorCode;
  final List<int> _durations = [];

  void record(int milliseconds, {String? errorCode}) {
    requests++;
    if (errorCode != null) {
      failures++;
      lastErrorCode = errorCode;
      if (errorCode == 'timeout') timeouts++;
    }
    _durations.add(milliseconds);
    if (_durations.length > 100) _durations.removeAt(0);
  }

  int get p95Milliseconds {
    if (_durations.isEmpty) return 0;
    final sorted = [..._durations]..sort();
    return sorted[(sorted.length * .95).ceil() - 1];
  }
}
