import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../domain/play_history_entry.dart';
import '../domain/playback_context.dart';

/// 播放历史 API 客户端。
///
/// 上下文标识（[PlaybackContext.key]）一律走 query 参数而非路径：歌手 / 专辑名里
/// 可能含 `/`、`%` 等字符，放进 URL 路径会有编解码歧义。
class PlayHistoryApi {
  final Dio dio;

  PlayHistoryApi(this.dio);

  Map<String, dynamic> _contextQuery(PlaybackContext context) => {
    'context_type': context.type,
    'context_key': context.key,
  };

  /// 查询某上下文的播放历史（按最后播放时间倒序，后端上限 50 条）。
  Future<List<PlayHistoryEntry>> getHistory(
    PlaybackContext context, {
    int? limit,
  }) async {
    final query = _contextQuery(context);
    if (limit != null && limit > 0) query['limit'] = limit;

    final response = await dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/play-history',
      queryParameters: query,
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items
        .map((e) => PlayHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 清空某上下文的播放历史，返回删除条数。
  Future<int> clearHistory(PlaybackContext context) async {
    final response = await dio.delete<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/play-history',
      queryParameters: _contextQuery(context),
    );
    return (response.data?['deleted'] as num?)?.toInt() ?? 0;
  }

  /// 删除某上下文里某首歌的播放记录。
  Future<void> deleteEntry(PlaybackContext context, int songId) async {
    await dio.delete(
      '${AppConfig.apiPrefix}/play-history/entry',
      queryParameters: {..._contextQuery(context), 'song_id': songId},
    );
  }
}
