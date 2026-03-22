class RetryManager {
  final int maxRetries = 3;

  Future<bool> executeWithRetry(Function task) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        await task();
        return true;
      } catch (e) {
        attempt++;
        if (attempt == maxRetries) {
          return false; // Hard failure
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return false;
  }
}
