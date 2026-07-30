import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/webview_environment.dart';
import '../../../core/utils/window_visibility.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'plugin_host_bridge.dart';
import 'plugin_theme_utils.dart';

/// 插件 Tab 页面（原生平台实现）
/// 在 Shell 内嵌入 WebView 展示插件页面，底部导航栏保持可见
class PluginTabPage extends ConsumerStatefulWidget {
  final String entryPath;
  final bool isActive;

  const PluginTabPage({
    super.key,
    required this.entryPath,
    this.isActive = true,
  });

  @override
  ConsumerState<PluginTabPage> createState() => _PluginTabPageState();
}

class _PluginTabPageState extends ConsumerState<PluginTabPage>
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
  // 重试计数：作为 InAppWebView 的 ValueKey，递增即重建整个 WebView 部件。
  // Windows 上 WebView 实例创建失败时 onWebViewCreated 不触发、_webViewController 恒为
  // null，controller.reload() 是 no-op；必须重建部件才能重新走环境创建。(songloft#271)
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
  void didUpdateWidget(covariant PluginTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      // 原生 WebView 即使被 Offstage 隐藏仍可在系统层面持有键盘焦点，
      // 释放焦点以防止抢夺 Flutter 输入法上下文
      _webViewController?.clearFocus();
    }
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
    final uri = Uri.parse(
      '${AppConfig.baseUrl}${AppConfig.basePath}/api/v1/jsplugin/${widget.entryPath}',
    );
    final query =
        Map<String, String>.from(uri.queryParameters)
          ..['embed'] = ''
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

    // 接管 Android 硬件返回键：优先让 WebView 内部后退，无更多历史时再退出
    // （songloft-org/songloft#273）。前提是 shell 子 Navigator 保持挂载，返回键
    // 才能分发到本页 PopScope——保活逻辑见 shell_layout.dart 对该 issue 的修复。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _webViewController;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
          return;
        }
        await SystemNavigator.pop();
      },
      child: SafeArea(
        bottom: false,
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
          // Android：关闭 Hybrid Composition，改用 Virtual Display 渲染。
          // 插件 Tab 的 WebView 靠 shell 层 Offstage 做保活（切走隐藏、切回复用，
          // songloft-org/songloft#273）。Hybrid Composition 下 WebView 是独立原生
          // 表面 + overlay surface 合成，反复 Offstage 切换后 overlay 会重建异常，
          // 把画在其上的底部 NavigationBar 抹成黑块（用户报「切出再返回菜单栏黑屏」）。
          // Virtual Display 把 WebView 渲染进 Flutter 纹理、完全在控件树内合成，
          // 无独立 overlay，Offstage 保活干净、nav bar 不再被抹黑。
          // 代价：Virtual Display 的 IME 支持弱于 Hybrid Composition，插件内文本
          // 输入（如搜索框）体验可能下降；需要重输入的场景走全屏 WebView 页
          // （plugin_webview_page_native，仍用默认 Hybrid Composition）。
          // iOS/macOS 忽略此项（WKWebView 无此问题）。
          useHybridComposition: false,
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
                // 重建整个 WebView 部件而非 controller.reload()：实例创建失败时
                // controller 为 null，reload 无效；换 key 强制重建才能重新创建实例。
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
