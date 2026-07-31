import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// GitHub 加速代理的统一套用与「失败降级直连」封装。
///
/// 背景：用户配置的加速代理可能整体失效（如 mirror.ghproxy.com 停服）或间歇
/// 抖动，若不降级，热更 manifest / 整包检查会静默失败。凡是「后端拉取」以外
/// 的前端直连 GitHub 请求都应走这里，代理失败时自动用原始 URL 直连重试一次。

/// 给 URL 套 GitHub 加速代理前缀（空/null 则原样返回），自动补结尾 `/`。
String applyGithubProxy(String rawUrl, String? proxy) {
  if (proxy == null || proxy.isEmpty) return rawUrl;
  final prefix = proxy.endsWith('/') ? proxy : '$proxy/';
  return '$prefix$rawUrl';
}

/// GET [rawUrl]（套 [proxy]）。设置了代理且请求失败（连接错/超时/非 2xx）时，
/// 打日志后改用原始 URL 直连重试一次；直连的结果/异常原样抛给调用方。
Future<Response<T>> githubGetWithProxyFallback<T>(
  Dio dio,
  String rawUrl, {
  String? proxy,
  Options? options,
}) async {
  final url = applyGithubProxy(rawUrl, proxy);
  if (url == rawUrl) {
    return dio.get<T>(rawUrl, options: options);
  }
  try {
    return await dio.get<T>(url, options: options);
  } on DioException catch (e) {
    debugPrint('[GithubProxy] 代理请求失败,降级直连重试: 失败URL=$url ($e)');
    return dio.get<T>(rawUrl, options: options);
  }
}

/// `dio.download` 版，语义同 [githubGetWithProxyFallback]。
/// 降级重试会从头下载并覆盖 [savePath]。
Future<void> githubDownloadWithProxyFallback(
  Dio dio,
  String rawUrl,
  String savePath, {
  String? proxy,
  ProgressCallback? onReceiveProgress,
}) async {
  final url = applyGithubProxy(rawUrl, proxy);
  if (url == rawUrl) {
    await dio.download(rawUrl, savePath, onReceiveProgress: onReceiveProgress);
    return;
  }
  try {
    await dio.download(url, savePath, onReceiveProgress: onReceiveProgress);
  } on DioException catch (e) {
    debugPrint('[GithubProxy] 代理下载失败,降级直连重试: 失败URL=$url ($e)');
    await dio.download(rawUrl, savePath, onReceiveProgress: onReceiveProgress);
  }
}
