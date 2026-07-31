import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songloft_flutter/core/network/github_proxy_fallback.dart';

/// 按 URL 决定行为的 fake adapter：记录请求顺序，可对指定 URL 抛错/返回状态码。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(String url) handler;
  final requestedUrls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requestedUrls.add(url);
    return handler(url);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: ['text/plain'],
  },
);

void main() {
  const raw = 'https://github.com/o/r/releases/download/dev/m.json';
  const proxy = 'https://p.example.com/';
  const proxied = '$proxy$raw';

  group('applyGithubProxy', () {
    test('空/null 代理原样返回', () {
      expect(applyGithubProxy(raw, null), raw);
      expect(applyGithubProxy(raw, ''), raw);
    });

    test('自动补结尾斜杠', () {
      expect(applyGithubProxy(raw, 'https://p.example.com'), proxied);
      expect(applyGithubProxy(raw, proxy), proxied);
    });
  });

  group('githubGetWithProxyFallback', () {
    test('代理返回 5xx 时降级直连', () async {
      final adapter = _FakeAdapter((url) {
        if (url == proxied) return ResponseBody.fromString('bad', 502);
        return _ok('direct-data');
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final resp = await githubGetWithProxyFallback<String>(
        dio,
        raw,
        proxy: proxy,
      );

      expect(resp.data, 'direct-data');
      expect(adapter.requestedUrls, [proxied, raw]);
    });

    test('代理抛连接异常时降级直连', () async {
      final adapter = _FakeAdapter((url) {
        if (url == proxied) {
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: url),
            reason: 'refused',
          );
        }
        return _ok('direct-data');
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final resp = await githubGetWithProxyFallback<String>(
        dio,
        raw,
        proxy: proxy,
      );

      expect(resp.data, 'direct-data');
      expect(adapter.requestedUrls, [proxied, raw]);
    });

    test('无代理时只请求一次且异常原样抛出', () async {
      final adapter = _FakeAdapter(
        (url) => ResponseBody.fromString('boom', 500),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        githubGetWithProxyFallback<String>(dio, raw),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requestedUrls, [raw]);
    });

    test('代理成功时不再直连', () async {
      final adapter = _FakeAdapter((url) => _ok('proxied-data'));
      final dio = Dio()..httpClientAdapter = adapter;

      final resp = await githubGetWithProxyFallback<String>(
        dio,
        raw,
        proxy: proxy,
      );

      expect(resp.data, 'proxied-data');
      expect(adapter.requestedUrls, [proxied]);
    });

    test('代理与直连都失败时抛直连的异常', () async {
      final adapter = _FakeAdapter(
        (url) => ResponseBody.fromString('boom', 500),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        githubGetWithProxyFallback<String>(dio, raw, proxy: proxy),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requestedUrls, [proxied, raw]);
    });
  });
}
