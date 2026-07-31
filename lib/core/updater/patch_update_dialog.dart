import 'package:flutter/material.dart';
import 'package:flutter_patcher/flutter_patcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart'
    show appPreferencesProvider;
import '../../features/settings/data/frontend_version_api.dart';
import '../../features/settings/presentation/providers/settings_provider.dart'
    show githubProxyProvider, frontendVersionCheckProvider;
import '../../l10n/app_localizations.dart';
import '../backend/embedded_backend_service.dart';
import '../backend/run_mode_provider.dart';
import '../network/api_client.dart' show dioProvider;
import '../router/app_router.dart';
import 'backend_patch_service.dart';
import 'channel_release_resolver.dart';
import 'patch_update_service.dart';

/// 启动更新检查的跨会话节流窗口：窗口内的冷启动直接早退，不打任何网络。
///
/// Android 上 App 被系统杀掉后冷启极频繁，没有这道闸每次冷启都要重跑一整轮
/// GitHub 请求。设置页的手动检查（`manual: true`）不受此限制。
const kPatchCheckThrottle = Duration(hours: 6);

/// 首帧后到发起检查之间的等待：让首页歌单/电台请求先落地，别和它们抢带宽。
const kPatchCheckStartupDelay = Duration(seconds: 4);

/// 检查阶段（两类补丁并行拉 manifest）的整体超时兜底。
///
/// 各 dio 自带 10s/30s 超时，且代理失败会降级直连重试（单请求最坏翻倍）；
/// stable 渠道还要先打一次 `/releases/latest`，串起来可能远超单次超时，
/// 这里给整个检查阶段一个上限。
const _kPatchCheckTimeout = Duration(seconds: 45);

/// 统一的启动更新检查 + 手动更新对话框（Android）。
///
/// [maybeShow] 每会话调用一次，把**前端补丁（flutter_patcher，libapp.so）**与
/// **后端补丁（Bundle 版，libgojni.so）**合并为一次体验：
/// 1. 并行检查两类补丁（同渠道/同 tag，各自未被忽略）→ 有任一 → 弹**一个**对话框，
///    列出待更新组件，一次「下载并更新」把可用补丁一起下载（前端 stage libapp.so、
///    后端 stage libgojni.so），完成后**只重启一次**（[EmbeddedBackendService.restartProcess]
///    真进程冷启：既让 flutter_patcher 的 libapp.so 生效，又触发 Application 预加载
///    libgojni.so）；
/// 2. 否则同渠道有更高整包版本（不可热更）→ 弹「不兼容」→ 跳设置页下 APK；
/// 3. 都没有 → 静默。
///
/// 两条调用路径语义不同，见 [maybeShow] 的 `manual` 参数。
class PatchUpdateDialog extends ConsumerStatefulWidget {
  const PatchUpdateDialog._({this.frontendPatch, this.backendPatch});

  /// 前端 flutter_patcher 补丁（libapp.so），无则 null。
  final PatchInfo? frontendPatch;

  /// 后端补丁（libgojni.so，仅 Bundle 版 Android），无则 null。
  final BackendPatchInfo? backendPatch;

  /// 检查并（有补丁时）弹出更新对话框。返回**是否弹出了补丁对话框**。
  ///
  /// - `manual: false`（启动路径）：受「启动时自动检查」开关与 [kPatchCheckThrottle]
  ///   节流约束；尊重用户点过的「忽略此版本」；无补丁时继续做整包版本检查并可能弹
  ///   「不兼容」对话框。
  /// - `manual: true`（设置页「检查客户端更新」）：跳过开关与节流；**绕过忽略名单**
  ///   （只是本次不过滤，并不清除 `ignored_*` 记录 —— 自动路径下该版本仍保持静默）；
  ///   无补丁时**不**做整包检查 —— 由调用方接手 `FrontendUpgradeDialog`，否则会
  ///   连弹两个对话框。
  ///
  /// 已知取舍：某版本被忽略后，手动入口会一直先弹出这个补丁对话框，因而够不到整包
  /// 版本信息（`if (shown) return`）。这是「先查补丁、有则弹补丁」的直接后果。
  static Future<bool> maybeShow(
    BuildContext context,
    WidgetRef ref, {
    bool manual = false,
  }) async {
    final prefs = await ref.read(appPreferencesProvider.future);

    // 自动路径下、写新时间戳之前的旧值。查到补丁却没能弹出来时用它回滚节流窗口。
    int? throttleStampToRestore;

    if (!manual) {
      if (!prefs.isAutoUpdateCheckEnabled()) {
        debugPrint('[Updater] maybeShow: 「启动时自动检查」已关闭,跳过');
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - prefs.getLastPatchCheckAt();
      // elapsed < 0 = 设备时钟被往回调过（改时区、NTP 校正一个原本错误的时钟、手动
      // 改日期），时间戳落在了未来。此时不放行就会一直被节流到真实时间追上那个假
      // 时间戳为止（可能几个月），且节流分支不重写时间戳、自己好不了。视为过期照常
      // 检查，下面重写 now 即自愈。
      if (elapsed >= 0 && elapsed < kPatchCheckThrottle.inMilliseconds) {
        debugPrint(
          '[Updater] maybeShow: 距上次检查仅 ${Duration(milliseconds: elapsed).inMinutes} 分钟,'
          '未到 ${kPatchCheckThrottle.inHours} 小时节流窗口,跳过',
        );
        return false;
      }
      // 刻意在发起检查**之前**写时间戳:checkPatch 内部把网络异常都吞成 null,
      // 调用方分不清「没补丁」和「查失败」。写在前面意味着一次失败要等一个节流窗口
      // 才重试 —— 弱网/被墙环境下不会每次冷启都白跑一轮,代价由设置页手动入口兜住。
      throttleStampToRestore = prefs.getLastPatchCheckAt();
      await prefs.setLastPatchCheckAt(now);
    }

    // 读持久化代理（用于抓 manifest）
    String proxy = '';
    try {
      proxy = await ref.read(githubProxyProvider.future);
    } catch (_) {}
    final proxyOrNull = proxy.isNotEmpty ? proxy : null;

    // —— 并行检查前端补丁（libapp.so）与后端补丁（libgojni.so）——
    // 共用一个 resolver:stable 渠道只查一次 /releases/latest。
    final resolver = ChannelReleaseResolver();
    final frontendService = PatchUpdateService(resolver: resolver);
    final backendService = BackendPatchService(
      appDio: ref.read(dioProvider),
      resolver: resolver,
    );

    // 后端补丁仅在本地模式有意义:远程模式下 /api/v1/version 是远端服务器版本,
    // 拿它与本地内嵌后端补丁比较无意义,还会误 stage 让崩溃回滚状态机误判。先确保
    // 持久化的运行模式已加载再读,避免启动早期误判为 remote。
    await ref.read(runModeProvider.notifier).ensureLoaded();
    final isLocalMode = ref.read(runModeProvider) == RunMode.local;

    debugPrint(
      '[Updater] maybeShow: manual=$manual proxy=${proxyOrNull ?? "(直连)"} '
      'frontend=${frontendService.isSupported} '
      'backend=${backendService.isSupported}(local=$isLocalMode)',
    );

    final results = await Future.wait<Object?>([
      frontendService.isSupported
          ? frontendService.checkPatch(githubProxy: proxyOrNull)
          : Future<PatchInfo?>.value(null),
      backendService.isSupported && isLocalMode
          ? backendService.checkPatch(githubProxy: proxyOrNull)
          : Future<BackendPatchInfo?>.value(null),
    ]).timeout(
      _kPatchCheckTimeout,
      onTimeout: () {
        debugPrint(
          '[Updater] maybeShow: 检查超时(${_kPatchCheckTimeout.inSeconds}s),视为无补丁',
        );
        return <Object?>[null, null];
      },
    );

    var frontendPatch = results[0] as PatchInfo?;
    var backendPatch = results[1] as BackendPatchInfo?;

    // 过滤「忽略此版本」—— 手动检查视为用户主动撤销忽略，不过滤。
    if (!manual) {
      if (frontendPatch != null &&
          frontendPatch.version == prefs.getIgnoredPatchVersion()) {
        debugPrint('[Updater] maybeShow: 前端补丁 ${frontendPatch.version} 已被忽略');
        frontendPatch = null;
      }
      if (backendPatch != null &&
          backendPatch.patchLabel == prefs.getIgnoredBackendPatchVersion()) {
        debugPrint('[Updater] maybeShow: 后端补丁 ${backendPatch.patchLabel} 已被忽略');
        backendPatch = null;
      }
    }

    if (frontendPatch != null || backendPatch != null) {
      // 查到了补丁但宿主已卸载（用户在检查途中登出 / 离开了设置页）。这次发现只能丢,
      // 但**不该连带吃掉节流窗口** —— 否则一次「恰好卸载」会把一个真实可用的补丁压
      // 6 小时。回滚时间戳让下次冷启重查。另外这里必须单独打日志:落到下面那条
      // 「无可热更补丁」会在排查时误导人,明明查到了。
      if (!context.mounted) {
        if (throttleStampToRestore != null) {
          await prefs.setLastPatchCheckAt(throttleStampToRestore);
        }
        debugPrint(
          '[Updater] maybeShow: 查到补丁(frontend=${frontendPatch?.version}, '
          'backend=${backendPatch?.patchLabel})但 context 已卸载,回滚节流时间戳,下次重查',
        );
        return false;
      }
      debugPrint(
        '[Updater] maybeShow: 弹出更新对话框(frontend=${frontendPatch?.version}, '
        'backend=${backendPatch?.patchLabel})',
      );
      await showDialog<void>(
        context: context,
        barrierDismissible: true, // 允许点外部关闭
        builder:
            (_) => PatchUpdateDialog._(
              frontendPatch: frontendPatch,
              backendPatch: backendPatch,
            ),
      );
      return true;
    }

    // 手动路径到此为止:整包检查交给调用方的 FrontendUpgradeDialog,它自带
    // 「正在检查 / 已是最新 / 检查失败」三态,在这里再弹一个会变成连弹两个对话框。
    if (manual) {
      debugPrint('[Updater] maybeShow: 无可热更补丁(手动),交调用方处理整包');
      return false;
    }

    debugPrint('[Updater] maybeShow: 无可热更补丁,转整包版本检查');

    // —— 同渠道整包新版本(不可热更)→ 引导下 APK ——
    try {
      final check = await ref.read(frontendVersionCheckProvider.future);
      if (check.hasUpdate &&
          check.latestVersion != prefs.getIgnoredClientVersion() &&
          context.mounted) {
        await _showIncompatibleDialog(context, ref, check);
      }
    } catch (_) {
      // 版本检查失败不打扰用户
    }
    return false;
  }

  @override
  ConsumerState<PatchUpdateDialog> createState() => _PatchUpdateDialogState();
}

enum _Status { idle, downloading, done, failed }

class _PatchUpdateDialogState extends ConsumerState<PatchUpdateDialog> {
  final _frontendService = PatchUpdateService();
  late final BackendPatchService _backendService = BackendPatchService(
    appDio: ref.read(dioProvider),
  );
  _Status _status = _Status.idle;
  double? _fraction;

  Future<void> _download() async {
    // GitHub 代理来自「设置 → 网络设置」的全局配置
    final proxy = await ref.read(githubProxyProvider.future);
    if (!mounted) return;
    final proxyOrNull = proxy.isEmpty ? null : proxy;
    setState(() {
      _status = _Status.downloading;
      _fraction = null;
    });

    var ok = true;

    // 1) 前端补丁（libapp.so）
    final fp = widget.frontendPatch;
    if (ok && fp != null) {
      // patchUrl 保持原始地址，applyPatch 内部套代理并在失败时降级直连
      ok = await _frontendService.applyPatch(
        fp,
        githubProxy: proxyOrNull,
        onProgress: (prog) {
          if (mounted) setState(() => _fraction = prog.fraction);
        },
      );
    }

    // 2) 后端补丁（libgojni.so）
    final bp = widget.backendPatch;
    if (ok && bp != null) {
      if (mounted) setState(() => _fraction = null);
      ok = await _backendService.downloadAndStage(
        bp,
        githubProxy: proxyOrNull,
        onProgress: (f) {
          if (mounted) setState(() => _fraction = f);
        },
      );
    }

    if (!mounted) return;
    setState(() => _status = ok ? _Status.done : _Status.failed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (_status) {
      case _Status.downloading:
        return AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: _fraction,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  _fraction != null
                      ? '${l10n.updateDownloading} ${(_fraction! * 100).toStringAsFixed(0)}%'
                      : l10n.updateDownloading,
                ),
              ),
            ],
          ),
        );
      case _Status.done:
        return AlertDialog(
          title: Text(l10n.updateReadyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.updateReadyBody),
              const SizedBox(height: 8),
              Text(
                l10n.updateRestartInterrupt,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateActionLater),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 真进程冷启：libapp.so 冷启生效 + Application 预加载 libgojni.so。
                EmbeddedBackendService.restartProcess();
              },
              child: Text(l10n.updateActionRestartNow),
            ),
          ],
        );
      case _Status.failed:
        return AlertDialog(
          title: Text(l10n.updateFoundTitle),
          content: Text(l10n.updateFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateActionLater),
            ),
            FilledButton(
              onPressed: () => setState(() => _status = _Status.idle),
              child: Text(l10n.commonRetry),
            ),
          ],
        );
      case _Status.idle:
        return AlertDialog(
          title: Text(l10n.updateFoundTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.updateComponentsHeader),
              const SizedBox(height: 8),
              if (widget.frontendPatch != null)
                _componentLine(
                  context,
                  l10n.updateComponentFrontend(widget.frontendPatch!.version),
                ),
              if (widget.backendPatch != null)
                _componentLine(
                  context,
                  l10n.updateComponentBackend(widget.backendPatch!.patchLabel),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _ignoreAndClose,
              child: Text(l10n.updateActionIgnore),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateActionLater),
            ),
            FilledButton(
              onPressed: _download,
              child: Text(l10n.updateActionDownload),
            ),
          ],
        );
    }
  }

  Future<void> _ignoreAndClose() async {
    final prefs = await ref.read(appPreferencesProvider.future);
    if (widget.frontendPatch != null) {
      await prefs.setIgnoredPatchVersion(widget.frontendPatch!.version);
    }
    if (widget.backendPatch != null) {
      await prefs.setIgnoredBackendPatchVersion(
        widget.backendPatch!.patchLabel,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _componentLine(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('• $text', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// 「版本不兼容,需下载新 APK」对话框:忽略 / 稍后 / 前往设置页下载。
Future<void> _showIncompatibleDialog(
  BuildContext context,
  WidgetRef ref,
  FrontendVersionCheck check,
) async {
  final l10n = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder:
        (ctx) => AlertDialog(
          title: Text(l10n.updateIncompatibleTitle),
          content: Text(
            l10n.updateIncompatibleBody(check.latestVersionDisplay),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await ref.read(appPreferencesProvider.future);
                await prefs.setIgnoredClientVersion(check.latestVersion);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(l10n.updateActionIgnore),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.updateActionLater),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ctx.go(AppRoutes.settings);
              },
              child: Text(l10n.updateActionGoDownload),
            ),
          ],
        ),
  );
}
