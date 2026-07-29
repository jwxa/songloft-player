import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../player/domain/player_state.dart';
import '../../player/presentation/providers/player_provider.dart';
import 'plugin_host_dispatch.dart';

/// 插件页 ↔ Flutter 宿主的**原生**桥接（客户端 SDK 的能力层，native 平台）。
///
/// 让在客户端 webview 中打开的插件页面调用宿主播放器能力（改写正在播放队列、
/// 播放控制、订阅播放状态等）。协议见 `@songloft/client-sdk` 与 `common.js`：
///   - JS → Dart：`flutter_inappwebview.callHandler('songloftHost', {ns, method, params})`
///     回调统一返回 `{ok:true, data}` 或 `{ok:false, error}`。
///   - Dart → JS：播放状态变更经 `window.postMessage({type:'songloft-player-state', state})`
///     推给页面（节流：仅关键字段变化时推送，避免进度每秒刷屏）。
///
/// 分发逻辑委托传输无关的 [PluginHostDispatcher]（与 Web/iframe 链路共用）。
/// 两个 native 插件页面（`plugin_tab_page_native` / `plugin_webview_page_native`）
/// 复用本 mixin，避免逻辑重复。Web 平台的 iframe 链路见 `plugin_tab_page_stub.dart`。
mixin PluginHostBridgeMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const String _handlerName = 'songloftHost';

  InAppWebViewController? _bridgeController;
  String? _lastPushedStateSig;
  PluginHostDispatcher? _dispatcher;

  PluginHostDispatcher get _hostDispatcher =>
      _dispatcher ??= PluginHostDispatcher(
        ref,
        platformName: _platformName(),
        onOpenPlayer: () async => context.go(AppRoutes.player),
      );

  /// 在 `onWebViewCreated` 里调用，注册 JS→Dart handler。
  void registerHostBridge(InAppWebViewController controller) {
    _bridgeController = controller;
    controller.addJavaScriptHandler(
      handlerName: _handlerName,
      callback: (args) {
        final req = (args.isNotEmpty && args[0] is Map)
            ? Map<String, dynamic>.from(args[0] as Map)
            : <String, dynamic>{};
        return _hostDispatcher.handleCall(req);
      },
    );
  }

  /// 在 `build()` 里调用，监听播放状态并推送给插件页。
  /// `ref.listen` 在 build 中调用是 Riverpod 的推荐用法，订阅生命周期由框架管理。
  void listenPlayerState() {
    ref.listen<PlayerState>(playerStateProvider, (prev, next) {
      final sig = _hostDispatcher.stateSignature(next);
      if (sig == _lastPushedStateSig) return;
      _lastPushedStateSig = sig;
      final controller = _bridgeController;
      if (controller == null) return;
      final json = jsonEncode(_hostDispatcher.stateToJson(next));
      controller.evaluateJavascript(
        source: "window.postMessage({type:'songloft-player-state',state:$json},'*')",
      );
    });
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
