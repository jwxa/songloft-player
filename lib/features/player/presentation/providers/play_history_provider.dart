import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/play_history_api.dart';
import '../../domain/play_history_entry.dart';
import '../../domain/playback_context.dart';

final playHistoryApiProvider = Provider<PlayHistoryApi>((ref) {
  return PlayHistoryApi(ref.watch(dioProvider));
});

/// 某播放上下文的播放历史。
///
/// autoDispose：历史面板是临时弹窗，每次打开都取最新数据
/// （与常驻的 playlistSongsProvider 相反）。
final playHistoryProvider = FutureProvider.autoDispose
    .family<List<PlayHistoryEntry>, PlaybackContext>((ref, context) {
      return ref.watch(playHistoryApiProvider).getHistory(context);
    });
