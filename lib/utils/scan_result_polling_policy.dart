class ScanResultPollingPolicy {
  static const Duration maxProcessingWindow = Duration(seconds: 90);
  static const Duration completedConsistencyWindow = Duration(seconds: 10);
  static const Duration earlyPollInterval = Duration(seconds: 1);
  static const Duration midPollInterval = Duration(seconds: 2);
  static const Duration latePollInterval = Duration(seconds: 3);
  static const Duration earlyPollCutoff = Duration(seconds: 8);
  static const Duration midPollCutoff = Duration(seconds: 30);

  const ScanResultPollingPolicy();

  bool shouldContinue(Duration elapsed) {
    return elapsed < maxProcessingWindow;
  }

  Duration nextDelay(Duration elapsed) {
    if (elapsed < earlyPollCutoff) {
      return earlyPollInterval;
    }
    if (elapsed < midPollCutoff) {
      return midPollInterval;
    }
    return latePollInterval;
  }
}
