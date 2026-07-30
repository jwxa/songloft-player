import '../../../../shared/models/song.dart';

/// 分页抓取函数签名：给定 offset 和 limit，返回一批歌曲。
typedef FetchPage = Future<List<Song>> Function(int offset, int limit);

/// 每批加载完成后的回调。
typedef OnBatchLoaded = void Function(List<Song> songs);

/// 后台队列加载器：管理 generation-based 竞态取消、分批抓取和环形拼装。
///
/// 纯 Dart 类，无 Flutter / Riverpod 依赖。
/// PlayerNotifier 持有一个实例，将 API 调用作为 [FetchPage] 传入。
class QueueLoader {
  /// 默认每批加载的歌曲数。
  static const int defaultPageSize = 100;

  /// 默认单批次最大重试次数。
  static const int defaultMaxRetries = 3;

  int _generation = 0;

  /// 当前 generation 值（供外部同步读取）。
  int get generation => _generation;

  /// 递增 generation，使所有进行中的加载任务在下一个 await 点检测到过期并退出。
  /// 返回新的 generation 值。
  int invalidate() => ++_generation;

  /// 检查给定 [generation] 是否已被后续操作取代。
  bool isSuperseded(int generation) => generation != _generation;

  /// 分批加载剩余歌曲。
  ///
  /// 从 [alreadyLoaded] 位置开始，每次抓取 [pageSize] 首，直到达到 [totalCount]
  /// 或 fetch 返回空列表。每批完成后调用 [onBatch]。
  ///
  /// 返回 true 表示加载正常完成（或全部加载完毕），false 表示被取代或失败。
  Future<bool> loadRemaining({
    required int generation,
    required int totalCount,
    required int alreadyLoaded,
    required FetchPage fetch,
    required OnBatchLoaded onBatch,
    int pageSize = defaultPageSize,
    int maxRetries = defaultMaxRetries,
  }) async {
    int offset = alreadyLoaded;
    try {
      while (offset < totalCount) {
        // 每次网络请求前检查代次
        if (isSuperseded(generation)) return false;

        List<Song>? batch;
        for (int retry = 0; retry < maxRetries; retry++) {
          try {
            batch = await fetch(offset, pageSize);
            break;
          } catch (e) {
            if (retry == maxRetries - 1) rethrow;
            await Future<void>.delayed(
              Duration(milliseconds: 500 * (retry + 1)),
            );
          }
        }

        // 网络请求返回后再次检查
        if (isSuperseded(generation)) return false;

        if (batch == null || batch.isEmpty) break;

        onBatch(batch);
        offset += batch.length;
      }
    } catch (_) {
      // 加载失败：与原代码行为一致——异常向上透传由调用方 catch
      return false;
    }
    return !isSuperseded(generation);
  }

  /// 环形加载：以 [targetIndex] 为中心旋转队列。
  ///
  /// 先加载 `[targetIndex+1, totalCount)` 区间（目标之后），
  /// 再加载 `[0, targetIndex)` 区间（回卷到开头直到目标之前）。
  /// 每批完成后调用 [onBatch]。
  ///
  /// 如果 [targetIndex] < 0（歌曲不在列表中），则加载 `[0, totalCount)` 全部。
  ///
  /// 返回 true 表示正常完成，false 表示被取代或失败。
  Future<bool> loadAroundSong({
    required int generation,
    required int targetIndex,
    required int totalCount,
    required FetchPage fetch,
    required OnBatchLoaded onBatch,
    int pageSize = defaultPageSize,
    int maxRetries = defaultMaxRetries,
  }) async {
    if (targetIndex < 0) {
      // 歌曲不在上下文中，加载整个范围
      return _appendRange(
        generation: generation,
        offset: 0,
        endExclusive: totalCount,
        fetch: fetch,
        onBatch: onBatch,
        pageSize: pageSize,
        maxRetries: maxRetries,
      );
    }

    // 先接上目标歌之后的部分，让「往下播」立刻可用
    final tailDone = await _appendRange(
      generation: generation,
      offset: targetIndex + 1,
      endExclusive: totalCount,
      fetch: fetch,
      onBatch: onBatch,
      pageSize: pageSize,
      maxRetries: maxRetries,
    );
    if (!tailDone) return false;

    // 再回卷补上开头到目标歌之前的部分
    return _appendRange(
      generation: generation,
      offset: 0,
      endExclusive: targetIndex,
      fetch: fetch,
      onBatch: onBatch,
      pageSize: pageSize,
      maxRetries: maxRetries,
    );
  }

  /// 分批抓取 `[offset, endExclusive)` 区间的歌曲。
  ///
  /// 返回 false 表示被新的播放操作抢占（代次过期）或抓取失败。
  Future<bool> _appendRange({
    required int generation,
    required int offset,
    required int endExclusive,
    required FetchPage fetch,
    required OnBatchLoaded onBatch,
    required int pageSize,
    required int maxRetries,
  }) async {
    var cursor = offset;
    while (cursor < endExclusive) {
      if (isSuperseded(generation)) return false;

      final limit = (endExclusive - cursor).clamp(1, pageSize);
      List<Song>? batch;
      for (var retry = 0; retry < maxRetries; retry++) {
        try {
          batch = await fetch(cursor, limit);
          break;
        } catch (e) {
          if (retry == maxRetries - 1) return false;
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (retry + 1)),
          );
        }
      }

      if (isSuperseded(generation)) return false;
      if (batch == null || batch.isEmpty) break;

      onBatch(batch);
      cursor += batch.length;
    }
    return !isSuperseded(generation);
  }
}
