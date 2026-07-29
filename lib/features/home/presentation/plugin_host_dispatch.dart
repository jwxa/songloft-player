import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../shared/models/song.dart';
import '../../library/presentation/providers/songs_provider.dart';
import '../../player/domain/player_state.dart';
import '../../player/presentation/providers/player_provider.dart';

/// 传输无关的插件宿主桥接分发器。
///
/// native（`flutter_inappwebview.callHandler`）与 web（iframe `postMessage`）两条
/// 传输链路共用同一套分发逻辑：解析 `{ns, method, params}` → 调用 [PlayerNotifier]
/// 既有能力 → 返回结果。
///
/// 本文件 **web-safe**：不 import `dart:io` / `flutter_inappwebview`，故可被
/// Web 平台的 stub 页面直接引用。平台名由调用方注入（native 传 `Platform.*`，web 传 `'web'`）。
class PluginHostDispatcher {
  PluginHostDispatcher(
    this.ref, {
    required this.platformName,
    this.onOpenPlayer,
  });

  final WidgetRef ref;
  final String platformName;
  final Future<void> Function()? onOpenPlayer;

  /// 处理一次调用，统一返回 `{ok:true, data}` 或 `{ok:false, error}`。
  Future<Map<String, dynamic>> handleCall(Map<String, dynamic> req) async {
    try {
      final ns = req['ns'] as String?;
      final method = req['method'] as String?;
      final params = (req['params'] is Map)
          ? Map<String, dynamic>.from(req['params'] as Map)
          : <String, dynamic>{};
      final data = await _dispatch(ns, method, params);
      return {'ok': true, 'data': data};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<dynamic> _dispatch(
    String? ns,
    String? method,
    Map<String, dynamic> p,
  ) async {
    if (ns == 'host') {
      switch (method) {
        case 'getInfo':
          return {
            'version': AppConfig.frontendVersion,
            'platform': platformName,
            'capabilities': ['player', 'navigation'],
          };
        case 'openPlayer':
          if (onOpenPlayer == null) {
            throw Exception('host navigation unavailable');
          }
          await onOpenPlayer!();
          return null;
      }
      throw Exception('unknown host method: $method');
    }

    if (ns == 'player') {
      final notifier = ref.read(playerStateProvider.notifier);
      switch (method) {
        case 'getState':
          return stateToJson(ref.read(playerStateProvider));

        case 'setQueue':
          {
            final songs = await _resolveSongs(_intList(p['ids']));
            if (songs.isEmpty) throw Exception('no valid songs resolved');
            final startIndex = (p['startIndex'] as num?)?.toInt() ?? 0;
            final srcId = (p['sourcePlaylistId'] as num?)?.toInt();
            await notifier.playPlaylist(
              songs,
              startIndex: startIndex,
              sourcePlaylistId: srcId,
            );
            return null;
          }

        case 'addToQueue':
          {
            final songs = await _resolveSongs(_intList(p['ids']));
            notifier.addToPlaylist(songs);
            return null;
          }

        case 'insertToQueue':
          {
            final index = (p['index'] as num).toInt();
            final songs = await _resolveSongs([(p['id'] as num).toInt()]);
            if (songs.isEmpty) throw Exception('song not found');
            notifier.insertToPlaylist(index, songs.first);
            return null;
          }

        case 'removeFromQueue':
          notifier.removeFromPlaylist((p['index'] as num).toInt());
          return null;

        case 'reorderQueue':
          notifier.reorderPlaylist(
            (p['oldIndex'] as num).toInt(),
            (p['newIndex'] as num).toInt(),
          );
          return null;

        case 'clearQueue':
          notifier.clearPlaylist();
          return null;

        case 'play':
          {
            final id = (p['id'] as num?)?.toInt();
            if (id != null) {
              final songs = await _resolveSongs([id]);
              if (songs.isEmpty) throw Exception('song not found');
              await notifier.playSong(songs.first);
            } else if (!ref.read(playerStateProvider).isPlaying) {
              await notifier.togglePlay();
            }
            return null;
          }

        case 'pause':
          if (ref.read(playerStateProvider).isPlaying) {
            await notifier.togglePlay();
          }
          return null;

        case 'togglePlay':
          await notifier.togglePlay();
          return null;

        case 'next':
          await notifier.playNext();
          return null;

        case 'prev':
          await notifier.playPrev();
          return null;

        case 'seek':
          await notifier.seek(
            Duration(milliseconds: ((p['seconds'] as num) * 1000).round()),
          );
          return null;

        case 'setVolume':
          await notifier.setVolume((p['volume'] as num).toDouble());
          return null;

        case 'setPlayMode':
          await notifier.setPlayMode(PlayMode.fromString(p['mode'] as String));
          return null;

        case 'playPlaylistById':
          return notifier.playPlaylistById((p['playlistId'] as num).toInt());
      }
      throw Exception('unknown player method: $method');
    }

    throw Exception('unknown namespace: $ns');
  }

  /// 播放状态序列化（推送给插件页 / getState 返回）。
  Map<String, dynamic> stateToJson(PlayerState s) {
    return {
      'queue': s.playlist.map((e) => e.toJson()).toList(),
      'current_index': s.currentIndex,
      'current_song': s.currentSong?.toJson(),
      'is_playing': s.isPlaying,
      'current_time': s.currentTime.inMilliseconds / 1000.0,
      'duration': s.duration.inMilliseconds / 1000.0,
      'volume': s.volume,
      'play_mode': s.playMode.toStorageString(),
      'source_playlist_id': s.sourcePlaylistId,
    };
  }

  /// 状态推送节流签名：仅关键字段变化时才推送，排除每秒变化的 currentTime。
  String stateSignature(PlayerState s) {
    return '${s.currentIndex}|${s.isPlaying}|${s.currentSong?.id}|'
        '${s.playMode}|${s.playlist.length}|${s.volume}';
  }

  /// 逐个解析歌曲 id 为完整 Song 对象；解析失败的 id 跳过，不阻断整批。
  Future<List<Song>> _resolveSongs(List<int> ids) async {
    final api = ref.read(songsApiProvider);
    final result = <Song>[];
    for (final id in ids) {
      try {
        result.add(await api.getSong(id));
      } catch (_) {
        // 跳过无法解析的歌曲
      }
    }
    return result;
  }

  List<int> _intList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<num>().map((e) => e.toInt()).toList(growable: false);
  }
}
