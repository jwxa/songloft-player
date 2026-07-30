import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/webview_environment.dart';
import '../../../core/utils/window_visibility.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'plugin_host_bridge.dart';
import 'plugin_theme_utils.dart';

/// 插件 WebView 页面（原生平台实现）
/// 在应用内加载插件 HTML 页面，通过 JS 注入传递 JWT token
class PluginWebViewPage extends ConsumerStatefulWidget {
  final String pluginUrl;
  final String pluginName;

  const PluginWebViewPage({
    super.key,
    required this.pluginUrl,
    required this.pluginName,
  });

  @override
  ConsumerState<PluginWebViewPage> createState() => _PluginWebViewPageState();
}

class _PluginWebViewPageState extends ConsumerState<PluginWebViewPage>
    with WidgetsBindingObserver, PluginHostBridgeMixin {
  static const Duration _pageLoadTimeout = Duration(seconds: 20);

  InAppWebViewController? _webViewController;
  Timer? _loadTimer;
  bool _isLoading = true;
  bool _pageReady = false;
  String? _errorMessage;
  String? _lastTheme;
  bool _windowVisible = true;
  // 窗口是否可见（最小化 / 隐藏到托盘时为 false）。Windows 上 WebView2 是独立原生
  // HWND，最小化后不自动收起、残留拦截桌面右键（songloft-org/songloft#293）；
  // Offstage 收不起 HWND，必须据此把 WebView 整个移出 widget 树来销毁。仅 Windows
  // 会翻转此值（WindowTrayManager 只在 Windows setup），其余平台恒为 true。
  bool _hwndVisible = windowVisibleNotifier.value;
  // 重试计数：作为 InAppWebView 的 ValueKey，递增即重建整个 WebView 部件，
  // 以恢复 Windows 上「实例创建失败→controller 为 null→reload 无效」的死循环。(songloft#271)
  int _reloadSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowVisibleNotifier.addListener(_onWindowVisibilityChanged);
    _startLoadTimer();
  }

  /// 窗口可见性变化（Windows 最小化 / 托盘）：不可见时下一帧 build 会把
  /// InAppWebView 移出 widget 树销毁 WebView2 HWND；恢复可见时重建并重新加载。
  void _onWindowVisibilityChanged() {
    final visible = windowVisibleNotifier.value;
    if (!mounted || _hwndVisible == visible) return;
    setState(() {
      _hwndVisible = visible;
      if (!visible) {
        // WebView 将被移出树，控制器随之失效，避免后续误用旧引用。
        _webViewController = null;
      } else {
        // 重新挂载：复位加载态并换 key 确保是全新实例，onLoadStart/Stop 会接管。
        _isLoading = true;
        _pageReady = false;
        _errorMessage = null;
        _reloadSeq++;
        _startLoadTimer();
      }
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    windowVisibleNotifier.removeListener(_onWindowVisibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state != AppLifecycleState.hidden;
    if (_windowVisible != visible) {
      setState(() => _windowVisible = visible);
    }
  }

  String _buildPluginUrl(String theme) {
    final token = SecureStorageService.cachedAccessToken ?? '';
    final uri = Uri.parse(widget.pluginUrl);
    final query = Map<String, String>.from(uri.queryParameters)
      ..['theme'] = theme;
    if (token.isNotEmpty) {
      query['access_token'] = token;
    }
    return uri.replace(queryParameters: query).toString();
  }

  void _startLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = Timer(_pageLoadTimeout, () {
      if (!mounted || !_isLoading) return;
      setState(() {
        _isLoading = false;
        _errorMessage = AppLocalizations.of(context).homePluginLoadTimeout;
      });
    });
  }

  void _finishLoading() {
    _loadTimer?.cancel();
    _loadTimer = null;
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _pageReady = true;
      _errorMessage = null;
    });
  }

  void _finishLoadingWithError(String message) {
    _loadTimer?.cancel();
    _loadTimer = null;
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _pageReady = false;
      _errorMessage = message;
    });
  }

  String _buildTokenInjectionScript() {
    final token = SecureStorageService.cachedAccessToken ?? '';
    if (token.isEmpty) return '';
    final escapedToken = token
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"');
    return "localStorage.setItem('songloft-auth', JSON.stringify({accessToken: '$escapedToken'}));";
  }

  void _sendThemeToPlugin(String theme) {
    _webViewController?.evaluateJavascript(
      source: "window.postMessage({type:'songloft-theme',theme:'$theme'},'*')",
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final theme = resolveEffectiveTheme(themeMode, brightness);

    listenPlayerState();

    if (_lastTheme == null) {
      _lastTheme = theme;
    } else if (_lastTheme != theme) {
      _lastTheme = theme;
      if (_pageReady) _sendThemeToPlugin(theme);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _webViewController;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pluginName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final controller = _webViewController;
              if (controller != null && await controller.canGoBack()) {
                await controller.goBack();
              } else if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: AppLocalizations.of(context).homePluginClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: AppLocalizations.of(context).homePluginOpenInBrowser,
              onPressed: () {
                final token = SecureStorageService.cachedAccessToken ?? '';
                final separator = widget.pluginUrl.contains('?') ? '&' : '?';
                var url = widget.pluginUrl;
                final params = <String>['theme=$theme'];
                if (token.isNotEmpty) params.add('access_token=$token');
                url = '$url$separator${params.join('&')}';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (_errorMessage != null)
                _buildErrorView(colorScheme)
              else if (_hwndVisible)
                _buildWebView(theme)
              else
                // 窗口不可见：不挂载 WebView，销毁原生 HWND（#293）。
                const SizedBox.expand(),
              if (_isLoading && _hwndVisible)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(String theme) {
    final tokenScript = _buildTokenInjectionScript();

    return Offstage(
      offstage: !_windowVisible,
      child: InAppWebView(
        key: ValueKey(_reloadSeq),
        webViewEnvironment: SongloftWebViewEnvironment.instance,
        initialUrlRequest: URLRequest(url: WebUri(_buildPluginUrl(theme))),
        initialUserScripts:
            tokenScript.isNotEmpty
                ? UnmodifiableListView([
                  UserScript(
                    source: tokenScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ])
                : null,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          supportZoom: false,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          registerHostBridge(controller);
        },
        onLoadStart: (controller, url) {
          if (mounted) {
            _startLoadTimer();
            setState(() {
              _isLoading = true;
              _pageReady = false;
              _errorMessage = null;
            });
          }
        },
        onLoadStop: (controller, url) {
          _finishLoading();
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame ?? false) {
            _finishLoadingWithError(error.description);
          }
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          if (request.isForMainFrame ?? false) {
            final status = errorResponse.statusCode;
            final reason = errorResponse.reasonPhrase;
            final detail = reason == null || reason.isEmpty ? '' : ' $reason';
            _finishLoadingWithError(
              AppLocalizations.of(
                context,
              ).homePluginLoadFailedHttp(status.toString(), detail),
            );
          }
        },
      ),
    );
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).homePluginLoadFailed,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ??
                  AppLocalizations.of(context).homePluginUnknownError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isLoading = true;
                // 重建整个 WebView 部件而非 controller.reload()（controller 可能为 null）。
                _reloadSeq++;
                _webViewController = null;
              });
              _startLoadTimer();
            },
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).commonRetry),
          ),
        ],
      ),
    );
  }
}
