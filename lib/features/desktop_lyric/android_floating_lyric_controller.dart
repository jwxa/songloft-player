import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/providers/auth_provider.dart';
import '../player/presentation/providers/lyric_provider.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'desktop_lyric_font_size.dart';

/// 主 isolate <-> 原生 WindowManager 悬浮窗的 MethodChannel（songloft-org/songloft#318）。
///
/// 手机上直接用一个原生 TextView overlay 实现悬浮歌词，不需要像 Windows 那样起第二个
/// Flutter engine。权限申请完全在 Dart 侧用 permission_handler 做，且只在设置开关打开
/// 的那一刻触发（见 settings_provider.dart），这个 channel 本身不涉及权限。
const MethodChannel floatingLyricChannel = MethodChannel(
  'com.songloft/floating_lyric',
);

/// Android 侧管理悬浮歌词窗口生命周期。
///
/// 接口形状照抄 [DesktopLyricController]，方便 settings_provider.dart 按平台分支调用；
/// 区别在于这里没有独立的悬浮窗 engine，锁定/字号/透明度的初始值也是由这里直接读取
/// AppPreferences 后随 show() 一起传给原生层，而不是像桌面端那样悬浮窗自己读一份。
class AndroidFloatingLyricController {
  AndroidFloatingLyricController(this._ref) {
    floatingLyricChannel.setMethodCallHandler(_handleMethodCall);
  }

  final Ref _ref;
  ProviderSubscription<LyricState>? _lyricSub;
  bool _isOpen = false;
  String _lastCurrent = '';
  String _lastNext = '';

  bool get isOpen => _isOpen;

  Future<bool> open() async {
    if (_isOpen) return true;
    final prefs = await _ref.read(appPreferencesProvider.future);
    final fontSize = DesktopLyricFontSizeX.fromStorageValue(
      prefs.getDesktopLyricFontSize(),
    );
    final posX = prefs.getDesktopLyricPosX();
    final posY = prefs.getDesktopLyricPosY();
    try {
      final ok = await floatingLyricChannel.invokeMethod<bool>('show', {
        'locked': prefs.getDesktopLyricLocked(),
        'mainSp': fontSize.mainTextSize,
        'subSp': fontSize.subTextSize,
        'opacity': prefs.getDesktopLyricOpacity(),
        'posX': posX,
        'posY': posY,
      });
      if (ok != true) return false;
    } catch (_) {
      return false;
    }
    _isOpen = true;
    _lastCurrent = '';
    _lastNext = '';
    _lyricSub = _ref.listen<LyricState>(lyricStateProvider, (prev, next) {
      _maybePushLyric(next);
    });
    _maybePushLyric(_ref.read(lyricStateProvider));
    return true;
  }

  Future<void> close() async {
    if (!_isOpen) return;
    _lyricSub?.close();
    _lyricSub = null;
    _isOpen = false;
    try {
      await floatingLyricChannel.invokeMethod('hide');
    } catch (_) {}
  }

  /// 悬浮窗已打开时，把最新的锁定/字号/透明度推给它实时生效。
  Future<void> pushConfig({
    required bool locked,
    required DesktopLyricFontSize fontSize,
    required double opacity,
  }) async {
    if (!_isOpen) return;
    try {
      await floatingLyricChannel.invokeMethod('updateConfig', {
        'locked': locked,
        'mainSp': fontSize.mainTextSize,
        'subSp': fontSize.subTextSize,
        'opacity': opacity,
      });
    } catch (_) {}
  }

  void _maybePushLyric(LyricState state) {
    if (!_isOpen) return;
    final current = state.currentLyricText;
    final next = state.nextLyricText;
    if (current == _lastCurrent && next == _lastNext) return;
    _lastCurrent = current;
    _lastNext = next;
    unawaited(
      floatingLyricChannel
          .invokeMethod('updateLyric', {'current': current, 'next': next})
          .catchError((_) {}),
    );
  }

  /// 通用扩展入口（对应 Kotlin 侧 `FloatingLyricPlugin.handleExec`）。
  /// 返回 null 表示当前 APK 不支持该子命令（优雅降级）。
  Future<T?> exec<T>(String cmd, [Map<String, dynamic>? params]) async {
    try {
      return await floatingLyricChannel.invokeMethod<T>('exec', {
        'cmd': cmd,
        if (params != null) ...params,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPositionChanged':
        final args = call.arguments as Map;
        final x = (args['x'] as num?)?.toDouble() ?? -1;
        final y = (args['y'] as num?)?.toDouble() ?? -1;
        final prefs = await _ref.read(appPreferencesProvider.future);
        await prefs.setDesktopLyricPosition(x, y);
      case 'onHideRequested':
        await _ref.read(desktopLyricEnabledProvider.notifier).setEnabled(false);
    }
    return null;
  }
}

/// 全局单例：整个 App 生命周期内只有一个悬浮歌词 Controller。
final androidFloatingLyricControllerProvider =
    Provider<AndroidFloatingLyricController>((ref) {
      return AndroidFloatingLyricController(ref);
    });
