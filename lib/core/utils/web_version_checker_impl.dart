import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 绕过缓存拉取服务端当前部署的前端版本标记（构建时由 build-frontend.sh 写入
/// 产物根目录的 version.json）。用于与烤进 bundle 的 AppConfig 值比对，判断
/// 浏览器是否仍在运行过期缓存。
///
/// 用 `cache: 'no-store'` 绕过 HTTP 缓存；version.json 不在 Service Worker 的
/// RESOURCES map 中（构建时于 flutter build 之后生成），故 SW 会网络透传，取到最新值。
/// 404 / 异常 / 非 2xx 一律返回 null（视为无法判断，调用方跳过）。
Future<({String version, String buildTime})?> fetchDeployedVersion() async {
  try {
    final url = '${_getBasePath()}version.json';
    final resp =
        await web.window
            .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
            .toDart;
    if (!resp.ok) return null;
    final text = (await resp.text().toDart).toDart;
    final data = jsonDecode(text);
    if (data is! Map) return null;
    final version = data['version'];
    final buildTime = data['buildTime'];
    if (version is! String || buildTime is! String) return null;
    return (version: version, buildTime: buildTime);
  } catch (_) {
    return null;
  }
}

const String _kReloadSentinelKey = 'songloft_update_reloaded';

/// 读取本会话已为哪个目标 buildTime 触发过清缓存刷新（防死循环，见 writeReloadSentinel）。
String? readReloadSentinel() {
  try {
    return web.window.sessionStorage.getItem(_kReloadSentinelKey);
  } catch (_) {
    return null;
  }
}

/// 记录本会话已为该目标 buildTime 清过一次缓存并刷新。若刷新后仍不匹配（SW 顽固），
/// 下次检测据此不再重复弹窗，避免「弹窗→刷新→仍旧→再弹」死循环。
void writeReloadSentinel(String buildTime) {
  try {
    web.window.sessionStorage.setItem(_kReloadSentinelKey, buildTime);
  } catch (_) {}
}

String _getBasePath() {
  final path = web.window.location.pathname;
  // 子路径部署（如 /songloft/）保留完整前缀；根路径返回 '/'
  if (path.endsWith('/')) return path;
  final lastSlash = path.lastIndexOf('/');
  return lastSlash >= 0 ? path.substring(0, lastSlash + 1) : '/';
}
