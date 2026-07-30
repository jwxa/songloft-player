import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/web_fullscreen.dart';
import '../../../../shared/models/song.dart';
import 'video_player_surface.dart';

/// 移动端横屏全屏视频页。
///
/// 原生(Android/iOS): 锁定横屏 + 沉浸式,退出时恢复竖屏与常规系统 UI。
/// Web: 通过浏览器 Fullscreen API 进入全屏(由 [VideoPlayerSurface] 在按钮点击
/// 时调用 [enterWebFullscreen] 触发),本页仅监听 `fullscreenchange` 事件以在
/// 用户按 Escape 退出全屏时自动 pop。
class VideoFullscreenPage extends ConsumerStatefulWidget {
  const VideoFullscreenPage({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                VideoFullscreenPage(song: song),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  ConsumerState<VideoFullscreenPage> createState() =>
      _VideoFullscreenPageState();
}

class _VideoFullscreenPageState extends ConsumerState<VideoFullscreenPage> {
  void Function()? _removeWebListener;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _removeWebListener = onWebFullscreenExit(() {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _removeWebListener?.call();
      exitWebFullscreen();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoPlayerSurface(song: widget.song, isFullscreen: true),
    );
  }
}
