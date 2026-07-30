/// 播放上下文：标识「当前队列是从哪儿播起来的」。
///
/// 用于播放历史（每个上下文各自记住最近播放过的歌曲，见 `/api/v1/play-history`）
/// 以及「正在播放」高亮。由 (type, key) 二元组唯一标识：
///
/// - 歌单：`PlaybackContext.playlist(3)` → `('playlist', '3')`
/// - 分面维度：`PlaybackContext('artist', '周杰伦')`
///
/// 曲库扁平列表（keyword + type 组合筛选）不构成稳定上下文，那种场景传 null。
class PlaybackContext {
  /// 上下文类型：`playlist` 或分面维度
  /// （`artist` / `album` / `genre` / `year` / `decade` / `language` / `style`）。
  final String type;

  /// 上下文标识：歌单存 ID 的字符串形式，分面维度存该维度的取值原文。
  final String key;

  const PlaybackContext(this.type, this.key);

  /// 歌单上下文的便捷构造。
  factory PlaybackContext.playlist(int playlistId) =>
      PlaybackContext(typePlaylist, '$playlistId');

  static const String typePlaylist = 'playlist';

  /// 该上下文对应的歌单 ID；非歌单上下文返回 null。
  int? get playlistId => type == typePlaylist ? int.tryParse(key) : null;

  Map<String, dynamic> toJson() => {'type': type, 'key': key};

  static PlaybackContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final type = json['type'];
    final key = json['key'];
    if (type is! String || key is! String || type.isEmpty || key.isEmpty) {
      return null;
    }
    return PlaybackContext(type, key);
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackContext && other.type == type && other.key == key;

  @override
  int get hashCode => Object.hash(type, key);

  @override
  String toString() => 'PlaybackContext($type, $key)';
}
