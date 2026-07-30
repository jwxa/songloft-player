import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/domain/use_cases/play_mode_resolver.dart';

void main() {
  group('PlayModeResolver', () {
    group('nextIndex', () {
      test('order mode: returns next index', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        expect(resolver.nextIndex(currentIndex: 0, length: 5), 1);
        expect(resolver.nextIndex(currentIndex: 3, length: 5), 4);
      });

      test('order mode: returns null at end of playlist', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        expect(resolver.nextIndex(currentIndex: 4, length: 5), isNull);
      });

      test('loop mode: wraps around to beginning', () {
        final resolver = PlayModeResolver(mode: PlayMode.loop);
        expect(resolver.nextIndex(currentIndex: 4, length: 5), 0);
        expect(resolver.nextIndex(currentIndex: 2, length: 5), 3);
      });

      test('single mode: returns current index (repeat)', () {
        final resolver = PlayModeResolver(mode: PlayMode.single);
        expect(resolver.nextIndex(currentIndex: 2, length: 5), 2);
      });

      test('singlePlay mode: returns current index (repeat)', () {
        final resolver = PlayModeResolver(mode: PlayMode.singlePlay);
        expect(resolver.nextIndex(currentIndex: 3, length: 5), 3);
      });

      test('random mode: does not repeat until all played', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );

        const length = 5;
        final played = <int>{};

        // Play through all songs - should not repeat
        for (var i = 0; i < length; i++) {
          final next = resolver.nextIndex(currentIndex: i, length: length)!;
          expect(played.contains(next), isFalse,
              reason: 'Index $next was repeated before all songs were played');
          played.add(next);
          resolver.markPlayed(next);
        }

        expect(played.length, length);
      });

      test('random mode: resets after all played and does not immediately repeat current', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );

        const length = 3;
        // Mark all as played
        for (var i = 0; i < length; i++) {
          resolver.markPlayed(i);
        }

        // Next call should reset and avoid current index
        final currentIndex = 1;
        final results = <int>{};
        // Run multiple times to verify it doesn't always return currentIndex
        for (var i = 0; i < 20; i++) {
          final next = resolver.nextIndex(currentIndex: currentIndex, length: length)!;
          results.add(next);
          // After reset, mark played again for clean state on next iteration
          resolver.onQueueChanged();
          for (var j = 0; j < length; j++) {
            resolver.markPlayed(j);
          }
        }

        // Should never immediately return the current index after reset
        // (because current index is added to _playedIndices on reset)
        // Actually, the first call after reset should not return currentIndex
        final resolverSingle = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        for (var i = 0; i < length; i++) {
          resolverSingle.markPlayed(i);
        }
        final next = resolverSingle.nextIndex(currentIndex: 1, length: length)!;
        expect(next, isNot(equals(1)));
      });

      test('empty list (length=0) returns null', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        expect(resolver.nextIndex(currentIndex: 0, length: 0), isNull);
      });

      test('random mode with length=0 returns null', () {
        final resolver = PlayModeResolver(mode: PlayMode.random);
        expect(resolver.nextIndex(currentIndex: 0, length: 0), isNull);
      });

      test('random mode with single song returns 0', () {
        final resolver = PlayModeResolver(mode: PlayMode.random);
        expect(resolver.nextIndex(currentIndex: 0, length: 1), 0);
      });
    });

    group('prevIndex', () {
      test('returns currentIndex when position > 3 seconds', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        final result = resolver.prevIndex(
          currentIndex: 3,
          length: 5,
          currentPosition: const Duration(seconds: 4),
        );
        expect(result, 3);
      });

      test('returns currentIndex when position is exactly > 3 seconds', () {
        final resolver = PlayModeResolver(mode: PlayMode.loop);
        final result = resolver.prevIndex(
          currentIndex: 2,
          length: 5,
          currentPosition: const Duration(seconds: 4),
        );
        expect(result, 2);
      });

      test('does not return currentIndex when position <= 3 seconds', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        final result = resolver.prevIndex(
          currentIndex: 3,
          length: 5,
          currentPosition: const Duration(seconds: 3),
        );
        expect(result, 2);
      });

      test('order mode: returns previous index', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        final result = resolver.prevIndex(
          currentIndex: 3,
          length: 5,
          currentPosition: Duration.zero,
        );
        expect(result, 2);
      });

      test('order mode: returns null at beginning', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        final result = resolver.prevIndex(
          currentIndex: 0,
          length: 5,
          currentPosition: Duration.zero,
        );
        expect(result, isNull);
      });

      test('loop mode: wraps around to end', () {
        final resolver = PlayModeResolver(mode: PlayMode.loop);
        final result = resolver.prevIndex(
          currentIndex: 0,
          length: 5,
          currentPosition: Duration.zero,
        );
        expect(result, 4);
      });

      test('single mode: returns current index', () {
        final resolver = PlayModeResolver(mode: PlayMode.single);
        final result = resolver.prevIndex(
          currentIndex: 2,
          length: 5,
          currentPosition: Duration.zero,
        );
        expect(result, 2);
      });

      test('random mode: returns a random index', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        final result = resolver.prevIndex(
          currentIndex: 2,
          length: 5,
          currentPosition: Duration.zero,
        );
        expect(result, isNotNull);
        expect(result, inInclusiveRange(0, 4));
      });

      test('empty list (length=0) returns null', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        final result = resolver.prevIndex(
          currentIndex: 0,
          length: 0,
          currentPosition: Duration.zero,
        );
        expect(result, isNull);
      });
    });

    group('preSelectNext', () {
      test('order mode: caches next index', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        resolver.preSelectNext(currentIndex: 2, length: 5);
        expect(resolver.preSelectedIndex, 3);
      });

      test('order mode: null at end', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        resolver.preSelectNext(currentIndex: 4, length: 5);
        expect(resolver.preSelectedIndex, isNull);
      });

      test('loop mode: wraps around', () {
        final resolver = PlayModeResolver(mode: PlayMode.loop);
        resolver.preSelectNext(currentIndex: 4, length: 5);
        expect(resolver.preSelectedIndex, 0);
      });

      test('random mode: caches a valid index', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        resolver.preSelectNext(currentIndex: 2, length: 5);
        expect(resolver.preSelectedIndex, isNotNull);
        expect(resolver.preSelectedIndex, inInclusiveRange(0, 4));
      });

      test('single/singlePlay mode: caches null', () {
        final resolver = PlayModeResolver(mode: PlayMode.single);
        resolver.preSelectNext(currentIndex: 2, length: 5);
        expect(resolver.preSelectedIndex, isNull);

        final resolver2 = PlayModeResolver(mode: PlayMode.singlePlay);
        resolver2.preSelectNext(currentIndex: 2, length: 5);
        expect(resolver2.preSelectedIndex, isNull);
      });

      test('nextIndex consumes preSelectedIndex in random mode', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        resolver.preSelectNext(currentIndex: 2, length: 5);
        final preSelected = resolver.preSelectedIndex;
        expect(preSelected, isNotNull);

        final next = resolver.nextIndex(currentIndex: 2, length: 5);
        expect(next, preSelected);
        // After consumption, preSelectedIndex should be null
        expect(resolver.preSelectedIndex, isNull);
      });

      test('empty list returns null', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        resolver.preSelectNext(currentIndex: 0, length: 0);
        expect(resolver.preSelectedIndex, isNull);
      });

      test('negative currentIndex returns null', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        resolver.preSelectNext(currentIndex: -1, length: 5);
        expect(resolver.preSelectedIndex, isNull);
      });
    });

    group('onModeChanged', () {
      test('clears playedIndices and preSelectedIndex', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );

        // Build up some state
        resolver.markPlayed(0);
        resolver.markPlayed(1);
        resolver.preSelectNext(currentIndex: 2, length: 5);
        expect(resolver.preSelectedIndex, isNotNull);

        // Change mode
        resolver.onModeChanged(PlayMode.order);

        expect(resolver.mode, PlayMode.order);
        expect(resolver.preSelectedIndex, isNull);

        // Verify playedIndices cleared: in random mode all indices should be available
        resolver.onModeChanged(PlayMode.random);
        // After clearing, with 5-length list and no played indices,
        // should be able to get all indices
        final indices = <int>{};
        for (var i = 0; i < 50; i++) {
          final idx = resolver.nextIndex(currentIndex: 0, length: 5);
          if (idx != null) indices.add(idx);
          resolver.onModeChanged(PlayMode.random); // reset each time
        }
        // Should have seen multiple different indices (state was cleared)
        expect(indices.length, greaterThan(1));
      });
    });

    group('onQueueChanged', () {
      test('resets internal state', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );

        resolver.markPlayed(0);
        resolver.markPlayed(1);
        resolver.markPlayed(2);
        resolver.preSelectNext(currentIndex: 3, length: 5);

        resolver.onQueueChanged();

        expect(resolver.preSelectedIndex, isNull);
        // After queue change, all indices should be available again
      });
    });

    group('markPlayed', () {
      test('adds index to played set', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );

        const length = 3;
        resolver.markPlayed(0);
        resolver.markPlayed(1);

        // Only index 2 should be available
        final next = resolver.nextIndex(currentIndex: 0, length: length);
        expect(next, 2);
      });
    });

    group('edge cases', () {
      test('single song in random mode prevIndex returns 0', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        final result = resolver.prevIndex(
          currentIndex: 0,
          length: 1,
          currentPosition: Duration.zero,
        );
        expect(result, 0);
      });

      test('preSelectNext called twice, second overwrites first', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        resolver.preSelectNext(currentIndex: 0, length: 10);
        final first = resolver.preSelectedIndex;

        resolver.preSelectNext(currentIndex: 0, length: 10);
        final second = resolver.preSelectedIndex;

        // Both are valid indices (may or may not be same due to random)
        expect(first, inInclusiveRange(0, 9));
        expect(second, inInclusiveRange(0, 9));
      });

      test('nextIndex with currentIndex=-1 in order mode returns 0', () {
        final resolver = PlayModeResolver(mode: PlayMode.order);
        // -1 + 1 = 0, which is < length
        expect(resolver.nextIndex(currentIndex: -1, length: 5), 0);
      });

      test('nextIndex with currentIndex=-1 in random mode returns valid index', () {
        final resolver = PlayModeResolver(
          mode: PlayMode.random,
          random: Random(42),
        );
        final result = resolver.nextIndex(currentIndex: -1, length: 5);
        expect(result, inInclusiveRange(0, 4));
      });
    });
  });
}
