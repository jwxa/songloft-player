import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/domain/use_cases/playback_retry_policy.dart';

void main() {
  late PlaybackRetryPolicy policy;

  setUp(() {
    policy = PlaybackRetryPolicy();
  });

  group('maxAttempts', () {
    test('local song allows up to 2 retries', () {
      expect(policy.maxAttempts(isNetworkSong: false), 2);
    });

    test('network song allows up to 7 retries', () {
      expect(policy.maxAttempts(isNetworkSong: true), 7);
    });
  });

  group('delay', () {
    test('local song always returns 1000ms', () {
      for (int attempt = 0; attempt < 5; attempt++) {
        expect(
          policy.delay(attempt: attempt, isNetworkSong: false),
          const Duration(milliseconds: 1000),
        );
      }
    });

    test('network song uses exponential back-off', () {
      // attempt 0: 2000 * 2^0 = 2000
      expect(
        policy.delay(attempt: 0, isNetworkSong: true),
        const Duration(milliseconds: 2000),
      );
      // attempt 1: 2000 * 2^1 = 4000
      expect(
        policy.delay(attempt: 1, isNetworkSong: true),
        const Duration(milliseconds: 4000),
      );
      // attempt 2: 2000 * 2^2 = 8000
      expect(
        policy.delay(attempt: 2, isNetworkSong: true),
        const Duration(milliseconds: 8000),
      );
    });

    test('network song delay is capped at 10000ms', () {
      // attempt 3: 2000 * 2^3 = 16000 → capped to 10000
      expect(
        policy.delay(attempt: 3, isNetworkSong: true),
        const Duration(milliseconds: 10000),
      );
      // attempt 6: 2000 * 2^6 = 128000 → capped to 10000
      expect(
        policy.delay(attempt: 6, isNetworkSong: true),
        const Duration(milliseconds: 10000),
      );
    });
  });

  group('consecutive failure tracking', () {
    test('starts at 0 failures', () {
      expect(policy.shouldStopCompletely, isFalse);
      expect(policy.consecutiveFailures, 0);
    });

    test('increments on onAllRetriesExhausted in order mode', () {
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.consecutiveFailures, 1);
    });

    test('3 consecutive failures triggers shouldStopCompletely', () {
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.shouldStopCompletely, isFalse);

      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.shouldStopCompletely, isTrue);
      expect(policy.consecutiveFailures, 3);
    });

    test('recordSuccess resets consecutive failures', () {
      policy.onAllRetriesExhausted(mode: PlayMode.loop);
      policy.onAllRetriesExhausted(mode: PlayMode.loop);
      expect(policy.consecutiveFailures, 2);

      policy.recordSuccess();
      expect(policy.consecutiveFailures, 0);
      expect(policy.shouldStopCompletely, isFalse);
    });

    test('reset clears all counters', () {
      policy.onAllRetriesExhausted(mode: PlayMode.random);
      policy.onAllRetriesExhausted(mode: PlayMode.random);
      policy.onAllRetriesExhausted(mode: PlayMode.random);
      expect(policy.shouldStopCompletely, isTrue);

      policy.reset();
      expect(policy.consecutiveFailures, 0);
      expect(policy.shouldStopCompletely, isFalse);
    });
  });

  group('onAllRetriesExhausted', () {
    test('single mode returns stop', () {
      final action = policy.onAllRetriesExhausted(mode: PlayMode.single);
      expect(action, FailureAction.stop);
    });

    test('singlePlay mode returns stop', () {
      final action = policy.onAllRetriesExhausted(mode: PlayMode.singlePlay);
      expect(action, FailureAction.stop);
    });

    test('order mode returns skipToNext', () {
      final action = policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(action, FailureAction.skipToNext);
    });

    test('loop mode returns skipToNext', () {
      final action = policy.onAllRetriesExhausted(mode: PlayMode.loop);
      expect(action, FailureAction.skipToNext);
    });

    test('random mode returns skipToNext', () {
      final action = policy.onAllRetriesExhausted(mode: PlayMode.random);
      expect(action, FailureAction.skipToNext);
    });

    test('single/singlePlay does not increment consecutive failures', () {
      policy.onAllRetriesExhausted(mode: PlayMode.single);
      policy.onAllRetriesExhausted(mode: PlayMode.singlePlay);
      expect(policy.consecutiveFailures, 0);
    });

    test('returns stop after 3 consecutive failures in order mode', () {
      expect(
        policy.onAllRetriesExhausted(mode: PlayMode.order),
        FailureAction.skipToNext,
      );
      expect(
        policy.onAllRetriesExhausted(mode: PlayMode.order),
        FailureAction.skipToNext,
      );
      expect(
        policy.onAllRetriesExhausted(mode: PlayMode.order),
        FailureAction.stop,
      );
    });
  });

  group('reset followed by re-accumulation', () {
    test('after reset, failures accumulate from 0 again', () {
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.consecutiveFailures, 2);

      policy.reset();
      expect(policy.consecutiveFailures, 0);

      // Accumulate again
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.consecutiveFailures, 1);
      expect(policy.shouldStopCompletely, isFalse);

      policy.onAllRetriesExhausted(mode: PlayMode.order);
      policy.onAllRetriesExhausted(mode: PlayMode.order);
      expect(policy.shouldStopCompletely, isTrue);
    });
  });

  group('interleaving modes', () {
    test('single mode does not affect consecutive count between order calls', () {
      policy.onAllRetriesExhausted(mode: PlayMode.order); // count = 1
      policy.onAllRetriesExhausted(mode: PlayMode.single); // count stays 1
      policy.onAllRetriesExhausted(mode: PlayMode.order); // count = 2
      expect(policy.consecutiveFailures, 2);
      expect(policy.shouldStopCompletely, isFalse);

      policy.onAllRetriesExhausted(mode: PlayMode.order); // count = 3
      expect(policy.shouldStopCompletely, isTrue);
    });
  });
}
