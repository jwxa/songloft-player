import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:songloft_flutter/core/utils/webview_environment.dart';

const _acceptanceUrl = String.fromEnvironment('GDSTUDIO_ACCEPTANCE_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_acceptanceUrl.isEmpty) {
      throw StateError('缺少 GDSTUDIO_ACCEPTANCE_URL');
    }
    await SongloftWebViewEnvironment.ensureInitialized();
  });

  testWidgets('GDStudio 核心流程可在真实 WebView 中完成', (tester) async {
    final controllerCompleter = Completer<InAppWebViewController>();
    final loadedCompleter = Completer<void>();
    final viewport = Platform.isAndroid
        ? const Size(412, 780)
        : const Size(1280, 800);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _AcceptanceApp(
        url: _acceptanceUrl,
        onController: controllerCompleter.complete,
        onLoaded: () {
          if (!loadedCompleter.isCompleted) loadedCompleter.complete();
        },
      ),
    );

    final controller = await controllerCompleter.future.timeout(
      const Duration(seconds: 30),
    );
    await loadedCompleter.future.timeout(const Duration(seconds: 30));
    await _waitFor(controller, "document.readyState === 'complete'");

    await _acceptConsent(controller);
    await _verifySettingsPersistence(controller);
    await _acceptConsent(controller);
    await _search(controller);
    await _verifyResponsiveLayout(controller, Platform.isAndroid);
    await _preview(controller);
    await _batchAdd(controller);
    await _download(controller);
    await _openMainPlayer(controller);
  }, timeout: const Timeout(Duration(minutes: 4)));
}

class _AcceptanceApp extends StatelessWidget {
  const _AcceptanceApp({
    required this.url,
    required this.onController,
    required this.onLoaded,
  });

  final String url;
  final ValueChanged<InAppWebViewController> onController;
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: InAppWebView(
            webViewEnvironment: SongloftWebViewEnvironment.instance,
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              supportZoom: false,
            ),
            onWebViewCreated: onController,
            onLoadStop: (_, __) => onLoaded(),
          ),
        ),
      ),
    );
  }
}

Future<void> _acceptConsent(InAppWebViewController controller) async {
  await _waitFor(controller, "document.querySelector('#consent-checkbox') !== null");
  await _run(controller, """
    const checkbox = document.querySelector('#consent-checkbox');
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change', { bubbles: true }));
    document.querySelector('#consent-accept').click();
  """);
  await _waitFor(controller, "document.querySelector('#consent-dialog').hidden");
}

Future<void> _verifySettingsPersistence(
  InAppWebViewController controller,
) async {
  await _run(controller, """
    const source = document.querySelector('[data-setting-source="tencent"]');
    source.checked = false;
    source.dispatchEvent(new Event('change', { bubbles: true }));
    document.querySelector('#download-template').value = 'downloads/{artist}/{title}';
    document.querySelector('#download-concurrency').value = '3';
    document.querySelector('#save-download-settings').click();
  """);
  await _waitFor(
    controller,
    "localStorage.getItem('acceptance-download-settings')?.includes('downloads/{artist}/{title}') === true",
  );
  await controller.reload();
  await _waitFor(controller, "document.readyState === 'complete'");
  await _waitFor(
    controller,
    "document.querySelector('[data-setting-source=\"tencent\"]')?.checked === false",
  );
  expect(
    await _bool(
      controller,
      "document.querySelector('#download-concurrency')?.value === '3'",
    ),
    isTrue,
  );
}

Future<void> _search(InAppWebViewController controller) async {
  await _run(controller, """
    document.querySelector('#keyword').value = 'So Cynical (Badum)';
    document.querySelector('#search-form').dispatchEvent(
      new Event('submit', { bubbles: true, cancelable: true })
    );
  """);
  await _waitFor(controller, "document.querySelectorAll('.track-row').length === 2");
  expect(
    await _text(controller, "document.querySelector('.track-title')?.textContent"),
    'So Cynical (Badum)',
  );
}

Future<void> _verifyResponsiveLayout(
  InAppWebViewController controller,
  bool narrow,
) async {
  final layout = await _json(controller, """
    (() => {
      const selectors = [
        '#search-button', '#batch-add', '#batch-download',
        '[data-preview-id]', '[data-library-id]', '[data-download-id]',
        '#save-download-settings'
      ];
      const controls = selectors.map(selector => {
        const element = document.querySelector(selector);
        const rect = element?.getBoundingClientRect();
        return { selector, width: rect?.width || 0, height: rect?.height || 0 };
      });
      return {
        controls,
        overflow: document.documentElement.scrollWidth - window.innerWidth,
        titleAlign: getComputedStyle(document.querySelector('.track-title')).textAlign,
        narrow: window.innerWidth < 600
      };
    })()
  """);
  expect(layout['overflow'] as num, lessThanOrEqualTo(1));
  expect(layout['titleAlign'], isNot('center'));
  expect(layout['narrow'], narrow);
  for (final control in layout['controls'] as List<dynamic>) {
    final item = control as Map<String, dynamic>;
    expect(item['width'] as num, greaterThan(0), reason: '${item['selector']} 不可见');
    expect(item['height'] as num, greaterThan(0), reason: '${item['selector']} 不可见');
  }
}

Future<void> _preview(InAppWebViewController controller) async {
  await _run(controller, "document.querySelector('[data-preview-id]').click()");
  await _waitFor(
    controller,
    "document.querySelector('#preview-audio')?.src.includes('/audio.wav') === true",
  );
  if (Platform.isAndroid) {
    await _waitFor(controller, "document.querySelector('#preview-play').hidden === false");
  }
  if (await _bool(controller, "document.querySelector('#preview-play').hidden === false")) {
    await _run(controller, "document.querySelector('#preview-play').click()");
  }
  await _waitFor(controller, "window.__acceptance.previewRequests > 0");
  await _run(controller, """
    fetch('/__state')
      .then(response => response.json())
      .then(state => { window.__acceptance.audioRequests = state.audioRequests; });
  """);
  await _waitFor(controller, 'window.__acceptance.audioRequests > 0');
  await _run(controller, """
    fetch('/__range-check', { headers: { Range: 'bytes=0-63' } })
      .then(response => { window.__acceptance.rangeOK = response.status === 206; });
  """);
  await _waitFor(controller, 'window.__acceptance.rangeOK === true');
  await _run(controller, "document.querySelector('#preview-stop').click()");
  await _waitFor(controller, "window.__acceptance.previewDeletes > 0");
}

Future<void> _batchAdd(InAppWebViewController controller) async {
  await _run(controller, """
    document.querySelectorAll('[data-select-key]').forEach(input => {
      input.checked = true;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
    document.querySelector('#batch-add').click();
  """);
  await _waitFor(controller, "document.querySelector('#status').textContent.includes('2 首已添加或复用')");
  expect(
    await _text(controller, "document.querySelector('[data-library-id]')?.textContent"),
    '主播放器播放',
  );
}

Future<void> _download(InAppWebViewController controller) async {
  await _run(controller, "document.querySelector('[data-download-id]').click()");
  await _waitFor(
    controller,
    "document.querySelector('.download-job-completed') !== null",
    timeout: const Duration(seconds: 15),
  );
  expect(
    await _text(controller, "document.querySelector('#download-queue-summary')?.textContent"),
    contains('1 已完成'),
  );
}

Future<void> _openMainPlayer(InAppWebViewController controller) async {
  await _run(controller, "document.querySelector('[data-library-id]').click()");
  await _waitFor(controller, "window.__acceptance.openPlayerCount === 1");
  final state = await _json(controller, 'window.__acceptance');
  expect(state['queue'], [101]);
  expect(state['openPlayerCount'], 1);
}

Future<void> _waitFor(
  InAppWebViewController controller,
  String expression, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await _bool(controller, expression)) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw TimeoutException('等待页面条件超时：$expression', timeout);
}

Future<bool> _bool(InAppWebViewController controller, String expression) async {
  final value = await controller.evaluateJavascript(
    source: 'String(Boolean($expression))',
  );
  return value == true || value?.toString().replaceAll('"', '') == 'true';
}

Future<String> _text(
  InAppWebViewController controller,
  String expression,
) async {
  final value = await controller.evaluateJavascript(
    source: "String($expression ?? '')",
  );
  return value?.toString().replaceAll(RegExp(r'^"|"$'), '') ?? '';
}

Future<Map<String, dynamic>> _json(
  InAppWebViewController controller,
  String expression,
) async {
  final value = await controller.evaluateJavascript(
    source: 'JSON.stringify($expression)',
  );
  if (value is Map<String, dynamic>) return value;
  var encoded = value?.toString() ?? '{}';
  if (encoded.startsWith('"') && encoded.endsWith('"')) {
    encoded = jsonDecode(encoded) as String;
  }
  return jsonDecode(encoded) as Map<String, dynamic>;
}

Future<void> _run(InAppWebViewController controller, String source) async {
  await controller.evaluateJavascript(source: '(() => { $source; return true; })()');
}
