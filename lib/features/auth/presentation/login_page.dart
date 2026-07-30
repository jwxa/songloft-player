import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../config/app_config.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/backend/embedded_backend_service.dart';
import '../../../core/backend/run_mode_provider.dart';
import '../../../core/network/base_url_provider.dart';
import '../../../core/network/insecure_tls_provider.dart';
import '../../../core/network/server_entry.dart';
import '../../../core/network/servers_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/secure_storage.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../domain/auth_state.dart';
import 'providers/auth_provider.dart';

/// 登录页面
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiUrlController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLocalModeBootstrapping = false;
  String _localModeHint = '';

  bool get _isApiUrlVisible => !AppConfig.isEmbedded;

  @override
  void initState() {
    super.initState();
    // 嵌入模式下 API 地址已由 main() 设定，无需加载存储的地址
    if (!AppConfig.isEmbedded) {
      _loadSavedApiUrl();
    }
    _loadSavedCredentials();

    // 本地模式下自动登录（token 过期回到登录页时，无需用户手动操作）
    if (_showLocalMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLoginLocal());
    }
  }

  Future<void> _loadSavedApiUrl() async {
    // 列表 1 项时预填该项的 url（与单地址旧版体验一致）。
    // 列表 ≥ 2 项时输入框被替换为下拉，无需预填。
    try {
      final servers = await ref.read(serversProvider.future);
      if (servers.length == 1 && servers.first.url.isNotEmpty) {
        _apiUrlController.text = servers.first.url;
      }
    } catch (_) {
      // 忽略
    }
  }

  Future<void> _loadSavedCredentials() async {
    // 优先从当前服务器的 ServerEntry 读取保存的凭证
    try {
      final currentUrl = ref.read(baseUrlProvider);
      final servers = await ref.read(serversProvider.future);
      final entry = servers.where((e) => e.url == currentUrl).firstOrNull;
      if (entry != null &&
          entry.username != null &&
          entry.username!.isNotEmpty) {
        _usernameController.text = entry.username!;
        if (entry.password != null) _passwordController.text = entry.password!;
        return;
      }
    } catch (_) {}
    // 兼容回退：全局 last 凭证
    final prefs = await ref.read(appPreferencesProvider.future);
    final savedUsername = prefs.getLastUsername();
    final savedPassword = prefs.getLastPassword();
    if (savedUsername != null && savedUsername.isNotEmpty) {
      _usernameController.text = savedUsername;
    }
    if (savedPassword != null && savedPassword.isNotEmpty) {
      _passwordController.text = savedPassword;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(authStateProvider.notifier);

    String? apiBaseUrl;
    if (!AppConfig.isEmbedded) {
      final servers = ref.read(serversProvider).value ?? const <ServerEntry>[];
      if (servers.length >= 2) {
        // 多服务器：使用 baseUrlProvider 为准
        apiBaseUrl = ref.read(baseUrlProvider);
      } else {
        // 0/1 项：使用单输入框的值
        final raw = _apiUrlController.text.trim();
        if (raw.isNotEmpty) {
          apiBaseUrl = raw.replaceAll(RegExp(r'/+$'), '');
        }
      }
    }

    await authNotifier.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      apiBaseUrl: apiBaseUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 监听认证状态变化，显示错误信息
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.error != null && next.error!.isNotEmpty) {
        ResponsiveSnackBar.showError(context, message: next.error!);
      }

      // 登录成功后跳转到首页
      if (next.status == AuthStatus.authenticated) {
        context.go(AppRoutes.home);
      }
    });

    // 本地模式自动登录中，显示加载界面
    if (_isLocalModeBootstrapping &&
        ref.read(runModeProvider) == RunMode.local) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/app_icon.png',
                width: 64,
                height: 64,
                semanticLabel: 'Songloft',
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_localModeHint),
            ],
          ),
        ),
      );
    }

    return _buildDefaultLayout(context, authState, theme, colorScheme);
  }

  // ========== 默认布局（手机/平板/桌面）==========

  Widget _buildDefaultLayout(
    BuildContext context,
    AuthState authState,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo 和标题
                    _buildHeader(theme, colorScheme),
                    const SizedBox(height: 48),

                    // 登录表单卡片
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 用户名输入框
                            _buildUsernameField(colorScheme),
                            const SizedBox(height: 16),

                            // 密码输入框
                            _buildPasswordField(colorScheme),
                            const SizedBox(height: 16),

                            // API 地址输入框 — 嵌入模式下隐藏，独立部署时显示
                            if (!AppConfig.isEmbedded)
                              _buildApiUrlField(colorScheme),
                            const SizedBox(height: 24),

                            // 登录按钮
                            _buildLoginButton(authState, colorScheme),
                          ],
                        ),
                      ),
                    ),

                    if (_showLocalMode) ...[
                      const SizedBox(height: 16),
                      _buildLocalModeButton(colorScheme),
                    ],

                    const SizedBox(height: 24),

                    // 底部提示
                    _buildFooter(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========== 共用 Widget 方法 ==========

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Logo
        Image.asset(
          'assets/icons/app_icon.png',
          width: 80,
          height: 80,
          semanticLabel: 'Songloft',
        ),
        const SizedBox(height: 24),
        Text(
          'Songloft',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).authLoginToContinue,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameField(ColorScheme colorScheme) {
    return TextFormField(
      controller: _usernameController,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).authUsername,
        hintText: AppLocalizations.of(context).authUsernameHint,
        prefixIcon: const Icon(Icons.person_outline),
      ),
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return AppLocalizations.of(context).authUsernameRequired;
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField(ColorScheme colorScheme) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).authPassword,
        hintText: AppLocalizations.of(context).authPasswordHint,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
          ),
          tooltip:
              _obscurePassword
                  ? AppLocalizations.of(context).authShowPassword
                  : AppLocalizations.of(context).authHidePassword,
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
      ),
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onFieldSubmitted: (_) => _handleLogin(),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppLocalizations.of(context).authPasswordRequired;
        }
        return null;
      },
    );
  }

  Widget _buildApiUrlField(ColorScheme colorScheme) {
    final servers = ref.watch(serversProvider).value ?? const <ServerEntry>[];
    final Widget field;
    if (servers.length >= 2) {
      final current = ref.watch(baseUrlProvider);
      final selected =
          servers.any((s) => s.url == current) ? current : servers.first.url;
      field = DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).authServer,
          prefixIcon: const Icon(Icons.cloud_outlined),
        ),
        items:
            servers
                .map(
                  (s) => DropdownMenuItem(
                    value: s.url,
                    child: Text(
                      s.name.isNotEmpty ? '${s.name} (${s.url})' : s.url,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
        onChanged: (url) {
          if (url != null) ref.read(baseUrlProvider.notifier).set(url);
        },
      );
    } else {
      field = TextFormField(
        controller: _apiUrlController,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).authApiUrl,
          hintText: AppConfig.baseUrl,
          prefixIcon: const Icon(Icons.cloud_outlined),
        ),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return AppLocalizations.of(context).authApiUrlRequired;
          }
          if (!value.startsWith('http://') && !value.startsWith('https://')) {
            return AppLocalizations.of(context).authInvalidUrl;
          }
          return null;
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [field, _buildInsecureTlsToggle()],
    );
  }

  /// 登录页内联的「忽略 SSL 证书校验」开关。
  ///
  /// 登录失败常因自签/无效证书，而设置页在登录守卫之后不可达，故在此提供入口。
  Widget _buildInsecureTlsToggle() {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(insecureTlsProvider);
    return CheckboxListTile(
      value: enabled,
      onChanged: (value) {
        ref.read(insecureTlsProvider.notifier).setValue(value ?? false);
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(l10n.settingsInsecureTlsTitle),
      subtitle: Text(l10n.settingsInsecureTlsSubtitle),
    );
  }

  Widget _buildLoginButton(AuthState authState, ColorScheme colorScheme) {
    return FilledButton(
      onPressed: authState.isLoading ? null : _handleLogin,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child:
          authState.isLoading
              ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
              : Text(AppLocalizations.of(context).authLogin),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Text(
      AppLocalizations.of(context).authCopyright(DateTime.now().year),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  // ========== 本地模式 ==========

  static const bool _showLocalMode = !kIsWeb && AppConfig.hasEmbeddedBackend;

  Future<void> _tryAutoLoginLocal() async {
    final runMode = ref.read(runModeProvider);
    if (runMode != RunMode.local) return;

    setState(() {
      _isLocalModeBootstrapping = true;
      _localModeHint = AppLocalizations.of(context).authAutoLoggingIn;
    });

    try {
      final running = await EmbeddedBackendService.isRunning();
      if (!running) {
        final musicDir = await EmbeddedBackendService.resolveMusicDir(
          ref.read(localMusicDirProvider),
        );
        if (musicDir == null || musicDir.isEmpty) return;
        await ref.read(localMusicDirProvider.notifier).set(musicDir);
        setState(
          () =>
              _localModeHint =
                  AppLocalizations.of(context).authStartingLocalBackend,
        );
        final dataDir = (await getApplicationSupportDirectory()).path;
        final port = await EmbeddedBackendService.start(
          dataDir: dataDir,
          musicDir: musicDir,
        );
        ref.read(baseUrlProvider.notifier).set('http://127.0.0.1:$port');

        final dio = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 2)),
        );
        for (var i = 0; i < 10; i++) {
          try {
            final baseUrl = ref.read(baseUrlProvider);
            final resp = await dio.get('$baseUrl/api/v1/health');
            if (resp.statusCode == 200) break;
          } catch (_) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        dio.close();
      }

      await ref
          .read(authStateProvider.notifier)
          .login(username: 'admin', password: 'admin');
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(
          context,
          message: AppLocalizations.of(
            context,
          ).authAutoLoginFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocalModeBootstrapping = false);
      }
    }
  }

  Widget _buildLocalModeButton(ColorScheme colorScheme) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _isLocalModeBootstrapping ? null : _handleLocalMode,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          icon:
              _isLocalModeBootstrapping
                  ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                  : const Icon(Icons.phone_android),
          label: Text(
            _isLocalModeBootstrapping
                ? _localModeHint
                : AppLocalizations.of(context).authUseLocalMode,
          ),
        ),
      ],
    );
  }

  Future<void> _handleLocalMode() async {
    setState(() {
      _isLocalModeBootstrapping = true;
      _localModeHint = AppLocalizations.of(context).authPreparing;
    });

    try {
      final musicDir = await EmbeddedBackendService.pickMusicDir(
        ref.read(localMusicDirProvider),
      );
      if (musicDir == null || musicDir.isEmpty) {
        setState(() => _isLocalModeBootstrapping = false);
        return;
      }
      await ref.read(localMusicDirProvider.notifier).set(musicDir);

      await ref.read(runModeProvider.notifier).set(RunMode.local);
      await EmbeddedBackendService.ensureStoragePermission();

      setState(
        () =>
            _localModeHint =
                AppLocalizations.of(context).authStartingLocalBackend,
      );
      final dataDir = (await getApplicationSupportDirectory()).path;
      final port = await EmbeddedBackendService.start(
        dataDir: dataDir,
        musicDir: musicDir,
      );

      final baseUrl = 'http://127.0.0.1:$port';
      ref.read(baseUrlProvider.notifier).set(baseUrl);

      setState(
        () => _localModeHint = AppLocalizations.of(context).authConnecting,
      );
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
      for (var i = 0; i < 10; i++) {
        try {
          final resp = await dio.get('$baseUrl/api/v1/health');
          if (resp.statusCode == 200) break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      dio.close();

      // 尝试恢复本地 session，有效则跳过登录
      final storage = SecureStorageService();
      final restored = await storage.restoreWallet(
        SecureStorageService.localWalletKey,
      );
      if (restored && !await storage.isAccessTokenExpired()) {
        ref.read(authStateProvider.notifier).setAuthenticated();
      } else {
        setState(
          () => _localModeHint = AppLocalizations.of(context).authLoggingIn,
        );
        final loginDio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 5),
          ),
        );
        final resp = await loginDio.post(
          '${AppConfig.apiPrefix}/auth/login',
          data: {'username': 'admin', 'password': 'admin'},
        );
        if (resp.statusCode == 200 && resp.data != null) {
          await storage.saveTokens(
            accessToken: resp.data['access_token'] ?? '',
            refreshToken: resp.data['refresh_token'] ?? '',
            expiresIn: resp.data['expires_in'] ?? 3600,
            walletKey: SecureStorageService.localWalletKey,
          );
        }
        loginDio.close();
        await ref.read(authStateProvider.notifier).checkAuth();
      }
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(
          context,
          message: AppLocalizations.of(
            context,
          ).authLocalModeFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocalModeBootstrapping = false);
      }
    }
  }
}
