import 'dart:async';

import '../player_state.dart';

/// 纯 Dart 睡眠定时逻辑，从 PlayerNotifier 中提取。
///
/// 职责：管理定时器生命周期、倒计时递减、按歌曲数模式计数。
/// 不持有任何 Flutter / Riverpod 依赖，方便独立单元测试。
class SleepTimerLogic {
  SleepTimerStatus? _status;
  Timer? _timer;
  Timer? _countdownTimer;

  /// 当前睡眠定时状态，外部可读取用于同步 UI state。
  SleepTimerStatus? get status => _status;

  /// 按时长设置睡眠定时。
  ///
  /// [duration] 倒计时总时长。
  /// [onExpired] 到期时的回调（调用方注入暂停逻辑）。
  /// [onTick] 每秒倒计时回调，传入剩余 Duration，用于更新 UI 显示。
  void startByDuration(
    Duration duration, {
    required void Function() onExpired,
    required void Function(Duration remaining) onTick,
  }) {
    cancel();

    _status = SleepTimerStatus(
      mode: SleepTimerMode.duration,
      remaining: duration,
    );

    _timer = Timer(duration, () {
      onExpired();
      cancel();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = _status;
      if (current == null || current.mode != SleepTimerMode.duration) {
        timer.cancel();
        return;
      }
      final remaining = current.remaining;
      if (remaining != null && remaining.inSeconds > 0) {
        final next = Duration(seconds: remaining.inSeconds - 1);
        _status = current.copyWith(remaining: next);
        onTick(next);
      } else {
        timer.cancel();
      }
    });
  }

  /// 按歌曲数设置睡眠定时。
  ///
  /// [count] 剩余歌曲数（含当前正在播放的曲）。
  void startAfterSongs(int count) {
    if (count < 1) return;
    cancel();
    _status = SleepTimerStatus(
      mode: SleepTimerMode.afterSongs,
      remainingSongs: count,
    );
  }

  /// 歌曲播放完成时调用。
  ///
  /// 返回 `true` 表示定时已到期，调用方应暂停播放。
  /// 返回 `false` 表示未到期或未设置 afterSongs 模式。
  bool onSongCompleted() {
    final current = _status;
    if (current == null || current.mode != SleepTimerMode.afterSongs) {
      return false;
    }
    final next = (current.remainingSongs ?? 1) - 1;
    if (next <= 0) {
      cancel();
      return true;
    }
    _status = current.copyWith(remainingSongs: next);
    return false;
  }

  /// 取消定时，清空所有状态。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _status = null;
  }

  /// 释放资源，等同于 [cancel]。在 Notifier dispose 时调用。
  void dispose() {
    cancel();
  }
}
