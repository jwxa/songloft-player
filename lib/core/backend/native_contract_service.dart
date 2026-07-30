import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// 原生契约哈希读取（安卓热更兼容闸）。
///
/// 设计见 docs/cn/backend_hotupdate.md「原生契约哈希闸」：
/// - 安卓热更只换 native .so（前端 libapp.so / 后端 libgojni.so），Kotlin 永不热更。
///   热更后的 Dart 若调用旧 APK 原生层不存在的 MethodChannel 方法会崩。
/// - 唯一能忠实反映「本地 APK 原生层支持什么」的信号，只能运行时从**不被热更**的
///   Kotlin 侧读取（Dart/Go 侧常量都会被补丁覆盖）。
/// - 原生侧 `com.songloft/contract` 的 `getHash` 返回 CI 构建期烧进 APK 的 asset 原文
///   `{"dart":"<sha>","go":"<sha>"}`。checkPatch 拿它与 manifest 里的哈希比对，不等即
///   拒绝热更（返回 null → 落整包）。
/// - **降级语义**：仅 Android 有实现；老宿主无此 channel（MissingPluginException）、
///   本地开发无 asset（空串）、非 Android → 全部返回 null，比对方**视为未知、不拦截**，
///   绝不因读不到而堵死所有热更。
class NativeContractService {
  NativeContractService._();

  static const _channel = MethodChannel('com.songloft/contract');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 读设备上 APK 的原生契约哈希，返回 `{dart, go}`（任一缺失为空串）。
  /// 读不到 / 不支持 → null（比对方降级不拦截）。
  static Future<Map<String, String>?> getHashes() async {
    if (!_isAndroid) return null;
    try {
      final json = await _channel.invokeMethod<String>('getHash');
      if (json == null || json.trim().isEmpty) return null;
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      return {
        'dart': (decoded['dart'] ?? '').toString(),
        'go': (decoded['go'] ?? '').toString(),
      };
    } on MissingPluginException {
      return null; // 老宿主 / 未实现 → 未知
    } on PlatformException catch (e) {
      debugPrint('[Contract] getHash 失败: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[Contract] getHash 解析失败: $e');
      return null;
    }
  }

  /// 门控前端 libapp.so 的 Dart↔原生契约哈希（空 = 未知）。
  static Future<String> dartHash() async => (await getHashes())?['dart'] ?? '';

  /// 门控后端 libgojni.so 的 Go 导出面契约哈希（空 = 未知）。
  static Future<String> goHash() async => (await getHashes())?['go'] ?? '';
}
