import '../../../shared/models/song.dart';

/// 某播放上下文内的一条播放历史记录。
class PlayHistoryEntry {
  final Song song;

  /// 最后一次播放时间（后端返回 UTC，展示时需 `.toLocal()`）。
  final DateTime playedAt;

  /// 在该上下文内的累计播放次数。
  final int playCount;

  const PlayHistoryEntry({
    required this.song,
    required this.playedAt,
    required this.playCount,
  });

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PlayHistoryEntry(
      song: Song.fromJson(json['song'] as Map<String, dynamic>),
      playedAt:
          DateTime.tryParse(json['played_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      playCount: (json['play_count'] as num?)?.toInt() ?? 1,
    );
  }
}
