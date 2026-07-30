import 'dart:math';

import '../player_state.dart';

/// Action to take when all retries for a song are exhausted.
enum FailureAction { stop, skipToNext }

/// Pure-domain retry policy for playback failures.
///
/// Encapsulates retry-count limits, back-off delay calculation, and
/// consecutive-failure tracking that were previously inlined in
/// [PlayerNotifier._playCurrent] / [PlayerNotifier._handlePlayFailure].
class PlaybackRetryPolicy {
  // ─── Configuration ───────────────────────────────────────────────────
  static const int _maxRetryLocal = 2;
  static const int _maxRetryNetwork = 7;
  static const int _retryDelayLocalMs = 1000;
  static const int _networkRetryBaseDelayMs = 2000;
  static const int _networkRetryMaxDelayMs = 10000;
  static const int _maxConsecutiveSkips = 3;

  // ─── State ───────────────────────────────────────────────────────────
  int _consecutiveFailures = 0;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Maximum number of retry attempts (excluding the initial attempt).
  int maxAttempts({required bool isNetworkSong}) =>
      isNetworkSong ? _maxRetryNetwork : _maxRetryLocal;

  /// Delay before the given retry [attempt] (0-based).
  ///
  /// - Local songs: fixed 1 000 ms.
  /// - Network songs: exponential back-off `base * 2^attempt` capped at 10 s.
  Duration delay({required int attempt, required bool isNetworkSong}) {
    if (!isNetworkSong) {
      return const Duration(milliseconds: _retryDelayLocalMs);
    }
    final ms = min(
      _networkRetryBaseDelayMs * pow(2, attempt).toInt(),
      _networkRetryMaxDelayMs,
    );
    return Duration(milliseconds: ms);
  }

  /// Call when a song plays successfully to reset the consecutive-failure
  /// counter.
  void recordSuccess() {
    _consecutiveFailures = 0;
  }

  /// Call when all retries for a song have been exhausted.
  ///
  /// Returns the action the player should take. Also increments the internal
  /// consecutive-failure counter (unless the mode is single/singlePlay, which
  /// always stops immediately without accumulating failures).
  FailureAction onAllRetriesExhausted({required PlayMode mode}) {
    if (mode == PlayMode.single || mode == PlayMode.singlePlay) {
      // Single modes stop immediately; don't accumulate failures.
      return FailureAction.stop;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxConsecutiveSkips) {
      return FailureAction.stop;
    }
    return FailureAction.skipToNext;
  }

  /// Whether consecutive failures have reached the threshold and playback
  /// should halt entirely.
  bool get shouldStopCompletely =>
      _consecutiveFailures >= _maxConsecutiveSkips;

  /// The current consecutive-failure count (exposed for error messages).
  int get consecutiveFailures => _consecutiveFailures;

  /// Resets all internal counters.
  void reset() {
    _consecutiveFailures = 0;
  }
}
