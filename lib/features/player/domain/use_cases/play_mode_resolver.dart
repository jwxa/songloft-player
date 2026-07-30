import 'dart:math';

import '../player_state.dart';

/// 播放模式解析器：负责根据当前播放模式计算下一首/上一首索引，
/// 以及维护随机播放已播放历史和预选缓存。
///
/// 纯 Dart 有状态类，不依赖 Flutter 或 Riverpod。
class PlayModeResolver {
  PlayModeResolver({
    required PlayMode mode,
    Random? random,
  })  : _mode = mode,
        _random = random ?? Random();

  final Random _random;
  PlayMode _mode;

  /// 随机模式下已播放的索引集合
  final Set<int> _playedIndices = {};

  /// 预选的下一首索引缓存
  int? _preSelectedNextIndex;

  /// 当前播放模式
  PlayMode get mode => _mode;

  /// 获取预选的下一首索引
  int? get preSelectedIndex => _preSelectedNextIndex;

  /// 根据当前模式计算下一首索引。
  /// 返回 null 表示播放停止（顺序模式到末尾、singlePlay 等情况）。
  int? nextIndex({required int currentIndex, required int length}) {
    if (length <= 0) return null;

    switch (_mode) {
      case PlayMode.order:
        final next = currentIndex + 1;
        return next < length ? next : null;
      case PlayMode.loop:
        return (currentIndex + 1) % length;
      case PlayMode.single:
      case PlayMode.singlePlay:
        return currentIndex;
      case PlayMode.random:
        final index = _preSelectedNextIndex ?? _getRandomIndex(
          currentIndex: currentIndex,
          length: length,
        );
        _preSelectedNextIndex = null;
        return index;
    }
  }

  /// 根据当前模式计算上一首索引。
  /// [currentPosition] 为当前播放位置，超过 3 秒时返回 currentIndex（表示重播当前歌曲）。
  /// 返回 null 表示无法再往前（顺序模式在第一首且 position <= 3s）。
  int? prevIndex({
    required int currentIndex,
    required int length,
    required Duration currentPosition,
  }) {
    if (length <= 0) return null;

    // 超过 3 秒，重播当前歌曲（seek to start）
    if (currentPosition.inSeconds > 3) {
      return currentIndex;
    }

    switch (_mode) {
      case PlayMode.order:
        final prev = currentIndex - 1;
        return prev >= 0 ? prev : null;
      case PlayMode.loop:
        return (currentIndex - 1 + length) % length;
      case PlayMode.single:
      case PlayMode.singlePlay:
        return currentIndex;
      case PlayMode.random:
        return _getRandomIndex(currentIndex: currentIndex, length: length);
    }
  }

  /// 预选下一首索引并缓存。
  /// 返回预选的索引值（也可通过 [preSelectedIndex] 获取）。
  int? preSelectNext({required int currentIndex, required int length}) {
    if (length <= 0 || currentIndex < 0) {
      _preSelectedNextIndex = null;
      return null;
    }

    switch (_mode) {
      case PlayMode.order:
        final next = currentIndex + 1;
        _preSelectedNextIndex = next < length ? next : null;
        break;
      case PlayMode.loop:
        _preSelectedNextIndex = (currentIndex + 1) % length;
        break;
      case PlayMode.random:
        _preSelectedNextIndex = _getRandomIndex(
          currentIndex: currentIndex,
          length: length,
        );
        break;
      case PlayMode.single:
      case PlayMode.singlePlay:
        _preSelectedNextIndex = null;
        break;
    }

    return _preSelectedNextIndex;
  }

  /// 模式切换时调用，清除已播放历史和预选缓存。
  void onModeChanged(PlayMode newMode) {
    _mode = newMode;
    _playedIndices.clear();
    _preSelectedNextIndex = null;
  }

  /// 队列变更时调用，重置内部状态。
  void onQueueChanged() {
    _playedIndices.clear();
    _preSelectedNextIndex = null;
  }

  /// 记录一个索引为已播放（外部切歌时调用）。
  void markPlayed(int index) {
    _playedIndices.add(index);
  }

  /// 获取随机索引（避免重复，直到全部播完再重置）
  int _getRandomIndex({required int currentIndex, required int length}) {
    if (length <= 1) return 0;

    // 如果所有歌曲都播放过，重置
    if (_playedIndices.length >= length) {
      _playedIndices.clear();
      // 保留当前索引，避免重置后立即重复当前歌曲
      if (currentIndex >= 0 && currentIndex < length) {
        _playedIndices.add(currentIndex);
      }
    }

    // 获取未播放的索引列表
    final availableIndices = List<int>.generate(length, (i) => i)
        .where((i) => !_playedIndices.contains(i))
        .toList();

    if (availableIndices.isEmpty) {
      return _random.nextInt(length);
    }

    return availableIndices[_random.nextInt(availableIndices.length)];
  }
}
