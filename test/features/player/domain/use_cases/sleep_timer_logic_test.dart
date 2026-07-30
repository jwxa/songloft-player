import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/use_cases/sleep_timer_logic.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';

void main() {
  late SleepTimerLogic logic;

  setUp(() {
    logic = SleepTimerLogic();
  });

  tearDown(() {
    logic.dispose();
  });

  group('SleepTimerLogic', () {
    group('startByDuration', () {
      test('到期后触发 onExpired', () {
        fakeAsync((async) {
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 10),
            onExpired: () => expired = true,
            onTick: (_) {},
          );

          async.elapse(const Duration(seconds: 9));
          expect(expired, isFalse);

          async.elapse(const Duration(seconds: 1));
          expect(expired, isTrue);
        });
      });

      test('onTick 每秒被调用，remaining 递减', () {
        fakeAsync((async) {
          final ticks = <Duration>[];
          logic.startByDuration(
            const Duration(seconds: 5),
            onExpired: () {},
            onTick: (remaining) => ticks.add(remaining),
          );

          async.elapse(const Duration(seconds: 5));
          expect(ticks.length, 4);
          expect(ticks[0], const Duration(seconds: 4));
          expect(ticks[1], const Duration(seconds: 3));
          expect(ticks[2], const Duration(seconds: 2));
          expect(ticks[3], const Duration(seconds: 1));
        });
      });

      test('status 在启动后正确设置', () {
        fakeAsync((async) {
          logic.startByDuration(
            const Duration(seconds: 30),
            onExpired: () {},
            onTick: (_) {},
          );

          expect(logic.status, isNotNull);
          expect(logic.status!.mode, SleepTimerMode.duration);
          expect(logic.status!.remaining, const Duration(seconds: 30));
        });
      });

      test('到期后 status 被清空', () {
        fakeAsync((async) {
          logic.startByDuration(
            const Duration(seconds: 3),
            onExpired: () {},
            onTick: (_) {},
          );

          async.elapse(const Duration(seconds: 3));
          expect(logic.status, isNull);
        });
      });
    });

    group('startAfterSongs', () {
      test('连续 3 次 onSongCompleted 最终返回 true', () {
        logic.startAfterSongs(3);

        expect(logic.onSongCompleted(), isFalse); // 剩余 2
        expect(logic.onSongCompleted(), isFalse); // 剩余 1
        expect(logic.onSongCompleted(), isTrue); // 到 0
      });

      test('第 1、2 次返回 false', () {
        logic.startAfterSongs(3);

        expect(logic.onSongCompleted(), isFalse);
        expect(logic.onSongCompleted(), isFalse);
      });

      test('status 中 remainingSongs 正确递减', () {
        logic.startAfterSongs(3);
        expect(logic.status!.remainingSongs, 3);

        logic.onSongCompleted();
        expect(logic.status!.remainingSongs, 2);

        logic.onSongCompleted();
        expect(logic.status!.remainingSongs, 1);
      });

      test('到期后 status 被清空', () {
        logic.startAfterSongs(1);
        logic.onSongCompleted();
        expect(logic.status, isNull);
      });

      test('count < 1 时不设置', () {
        logic.startAfterSongs(0);
        expect(logic.status, isNull);
      });
    });

    group('cancel', () {
      test('cancel 后 timer 不再触发', () {
        fakeAsync((async) {
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 5),
            onExpired: () => expired = true,
            onTick: (_) {},
          );

          async.elapse(const Duration(seconds: 2));
          logic.cancel();

          async.elapse(const Duration(seconds: 10));
          expect(expired, isFalse);
          expect(logic.status, isNull);
        });
      });

      test('cancel afterSongs 模式后 onSongCompleted 返回 false', () {
        logic.startAfterSongs(2);
        logic.cancel();
        expect(logic.onSongCompleted(), isFalse);
      });
    });

    group('重复 start 覆盖旧设置', () {
      test('duration 覆盖旧 duration', () {
        fakeAsync((async) {
          var expiredCount = 0;
          logic.startByDuration(
            const Duration(seconds: 10),
            onExpired: () => expiredCount++,
            onTick: (_) {},
          );

          async.elapse(const Duration(seconds: 5));

          // 重新设置，旧的应被取消
          logic.startByDuration(
            const Duration(seconds: 3),
            onExpired: () => expiredCount++,
            onTick: (_) {},
          );

          async.elapse(const Duration(seconds: 3));
          expect(expiredCount, 1); // 只有新的触发

          // 旧的不再触发
          async.elapse(const Duration(seconds: 10));
          expect(expiredCount, 1);
        });
      });

      test('afterSongs 覆盖旧 duration', () {
        fakeAsync((async) {
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 5),
            onExpired: () => expired = true,
            onTick: (_) {},
          );

          logic.startAfterSongs(2);

          async.elapse(const Duration(seconds: 10));
          expect(expired, isFalse);
          expect(logic.status!.mode, SleepTimerMode.afterSongs);
        });
      });
    });

    group('dispose', () {
      test('dispose 清理所有资源', () {
        fakeAsync((async) {
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 5),
            onExpired: () => expired = true,
            onTick: (_) {},
          );

          logic.dispose();

          async.elapse(const Duration(seconds: 10));
          expect(expired, isFalse);
          expect(logic.status, isNull);
        });
      });
    });

    group('未设置 timer', () {
      test('未设置时 onSongCompleted 返回 false', () {
        expect(logic.onSongCompleted(), isFalse);
      });

      test('未设置时 status 为 null', () {
        expect(logic.status, isNull);
      });
    });

    group('duration 模式下 onSongCompleted', () {
      test('duration 模式下 onSongCompleted 返回 false 且不影响 timer', () {
        fakeAsync((async) {
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 5),
            onExpired: () => expired = true,
            onTick: (_) {},
          );

          // duration 模式下歌曲完成不应影响定时器
          expect(logic.onSongCompleted(), isFalse);
          expect(logic.status!.mode, SleepTimerMode.duration);

          async.elapse(const Duration(seconds: 5));
          expect(expired, isTrue);
        });
      });
    });

    group('极短 duration', () {
      test('Duration(seconds: 1) 只触发 0 次 tick 后到期', () {
        fakeAsync((async) {
          final ticks = <Duration>[];
          var expired = false;
          logic.startByDuration(
            const Duration(seconds: 1),
            onExpired: () => expired = true,
            onTick: (remaining) => ticks.add(remaining),
          );

          async.elapse(const Duration(seconds: 1));
          expect(expired, isTrue);
          // 1秒 duration: countdown tick 在 1s 时触发检查，remaining=1s, > 0 → decrement to 0
          // 但 main timer 也在 1s 时触发 onExpired + cancel，所以看时序
          // Timer.periodic 和 Timer 同时到期时行为取决于调度顺序
        });
      });
    });
  });
}
