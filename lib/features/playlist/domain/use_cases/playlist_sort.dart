import '../playlist.dart';
import '../../../../shared/models/song.dart';

/// 从文本中提取第一个出现的数字（支持开头和中间位置）。
/// 例如: "04.校园故事" → 4, "干得漂亮 | 01 好意被辜负" → 1
/// 如果没有数字，返回 null。
int? extractLeadingNumber(String text) {
  final match = RegExp(r'(\d+)').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// 歌单排序 domain use case。
///
/// 纯 Dart 逻辑，不依赖 Flutter 框架。所有排序方法在排序结果与原始顺序相同时
/// 返回 null，以避免无效的 API 调用。
///
/// 通过构造函数注入自定义字符串比较器可支持 locale-aware 排序（如中文拼音排序）。
/// 默认使用大小写不敏感的 Unicode code point 排序。
///
/// 示例：注入拼音比较器实现中文歌名按拼音排序
/// ```dart
/// final sorter = PlaylistSort(
///   compareStrings: (a, b) => pinyinCompare(a, b),
/// );
/// ```
class PlaylistSort {
  final int Function(String a, String b) _compareStrings;

  /// 创建排序实例。
  ///
  /// [compareStrings] - 自定义字符串比较器，用于名称排序。
  /// 默认使用大小写不敏感的 [String.compareTo]（ASCII/Unicode 序）。
  /// 传入自定义比较器可支持拼音排序等 locale-aware 排序。
  PlaylistSort({int Function(String a, String b)? compareStrings})
      : _compareStrings = compareStrings ?? _defaultCompare;

  /// 默认比较器：大小写不敏感的 Unicode code point 顺序。
  static int _defaultCompare(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  /// 按歌曲名称排序，返回排序后的 song ID 列表。
  /// 如果已经是目标顺序则返回 null（避免无效 API 调用）。
  List<int>? sortSongsByName(List<Song> songs, {bool ascending = true}) {
    final sorted = List<Song>.from(songs)..sort((a, b) {
      final result = _compareStrings(a.title, b.title);
      return ascending ? result : -result;
    });

    final sortedIds = sorted.map((s) => s.id).toList();
    final originalIds = songs.map((s) => s.id).toList();

    if (_listEquals(sortedIds, originalIds)) return null;
    return sortedIds;
  }

  /// 按歌曲名称开头的数字排序（如 "01. xxx", "02. xxx"）。
  /// 无数字前缀的歌曲排在有前缀的后面，二者内部再按名称字母序。
  /// 已有序则返回 null。
  List<int>? sortSongsByNumberPrefix(List<Song> songs) {
    final sorted = List<Song>.from(songs)..sort((a, b) {
      final numA = extractLeadingNumber(a.title);
      final numB = extractLeadingNumber(b.title);

      // 都有数字前缀：按数值排序
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
        // 数值相同时按标题排序（使用自定义比较器）
        return _compareStrings(a.title, b.title);
      }
      // 有数字前缀的排在前面
      if (numA != null) return -1;
      if (numB != null) return 1;
      // 都没有数字前缀：按标题排序（使用自定义比较器）
      return _compareStrings(a.title, b.title);
    });

    final sortedIds = sorted.map((s) => s.id).toList();
    final originalIds = songs.map((s) => s.id).toList();

    if (_listEquals(sortedIds, originalIds)) return null;
    return sortedIds;
  }

  /// 按歌单名称排序，返回排序后的 playlist ID 列表。
  /// 已有序则返回 null。
  List<int>? sortPlaylistsByName(
    List<Playlist> playlists, {
    bool ascending = true,
  }) {
    final sorted = List<Playlist>.from(playlists)..sort((a, b) {
      final result = _compareStrings(a.name, b.name);
      return ascending ? result : -result;
    });

    final sortedIds = sorted.map((p) => p.id).toList();
    final originalIds = playlists.map((p) => p.id).toList();

    if (_listEquals(sortedIds, originalIds)) return null;
    return sortedIds;
  }

  /// 按歌单名称中的数字前缀排序，返回排序后的 playlist ID 列表。
  /// 无数字的歌单排在有数字的后面，二者内部再按名称字母序。
  /// 已有序则返回 null。
  List<int>? sortPlaylistsByNumberPrefix(List<Playlist> playlists) {
    final sorted = List<Playlist>.from(playlists)..sort((a, b) {
      final numA = extractLeadingNumber(a.name);
      final numB = extractLeadingNumber(b.name);

      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
        return _compareStrings(a.name, b.name);
      }
      if (numA != null) return -1;
      if (numB != null) return 1;
      return _compareStrings(a.name, b.name);
    });

    final sortedIds = sorted.map((p) => p.id).toList();
    final originalIds = playlists.map((p) => p.id).toList();

    if (_listEquals(sortedIds, originalIds)) return null;
    return sortedIds;
  }

  /// 简单的整数列表比较（避免依赖 flutter/foundation 的 listEquals）。
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
