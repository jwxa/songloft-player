import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songloft_flutter/core/network/api_client.dart' show dioProvider;
import 'package:songloft_flutter/core/storage/app_preferences.dart';
import 'package:songloft_flutter/core/updater/patch_update_dialog.dart';
import 'package:songloft_flutter/features/auth/presentation/providers/auth_provider.dart'
    show appPreferencesProvider;
import 'package:songloft_flutter/features/settings/presentation/providers/settings_provider.dart'
    show githubProxyProvider, GithubProxyNotifier;

/// 记录被读取次数的 githubProxy 假实现。
///
/// 「更新检查有没有真的往下走」的判定点：`maybeShow` 过了开关闸与节流闸之后，第一件
/// 事就是读 GitHub 代理配置。读了 = 闸门放行，没读 = 被拦在闸门外。
class _CountingGithubProxy extends GithubProxyNotifier {
  static int reads = 0;

  @override
  Future<String> build() async {
    reads++;
    return '';
  }
}

/// 把 [PatchUpdateDialog.maybeShow] 挂进一棵最小 widget 树里跑一次，返回其结果。
///
/// maybeShow 需要能弹对话框的 BuildContext 与 WidgetRef，无法当纯函数调用；这里用
/// Consumer 拿 ref、用 Builder 下的 Scaffold 拿 context。
Future<bool> _runMaybeShow(
  WidgetTester tester,
  AppPreferences prefs, {
  required bool manual,
}) async {
  bool? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWith((ref) async => prefs),
        githubProxyProvider.overrideWith(_CountingGithubProxy.new),
        dioProvider.overrideWithValue(Dio()),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return Scaffold(
              body: Builder(
                builder: (inner) {
                  // 首帧后触发，确保 Navigator 就绪（与 ShellLayout 的调用时机一致）
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    result = await PatchUpdateDialog.maybeShow(
                      inner,
                      ref,
                      manual: manual,
                    );
                  });
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  // 让 post-frame 回调与其中的所有 await 跑完
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
  return result ?? (fail('maybeShow 未完成'));
}

void main() {
  late AppPreferences prefs;

  setUp(() async {
    _CountingGithubProxy.reads = 0;
    SharedPreferences.setMockInitialValues({});
    prefs = await AppPreferences.create();
  });

  group('启动更新检查的三道闸', () {
    testWidgets('缺省状态：开关开启 + 从未检查过 → 放行，并落下节流时间戳', (tester) async {
      expect(prefs.isAutoUpdateCheckEnabled(), isTrue, reason: '开关应缺省开启');
      expect(prefs.getLastPatchCheckAt(), 0);

      final shown = await _runMaybeShow(tester, prefs, manual: false);

      expect(shown, isFalse, reason: '测试平台非 Android，无补丁可弹');
      expect(_CountingGithubProxy.reads, 1, reason: '应放行到读代理配置');
      expect(
        prefs.getLastPatchCheckAt(),
        greaterThan(0),
        reason: '放行后必须落时间戳，否则下次冷启还会全量重查',
      );
    });

    testWidgets('开关关闭 → 拦在闸门外，一个网络请求都不发', (tester) async {
      await prefs.setAutoUpdateCheckEnabled(false);

      final shown = await _runMaybeShow(tester, prefs, manual: false);

      expect(shown, isFalse);
      expect(_CountingGithubProxy.reads, 0, reason: '开关关闭不应读任何配置');
      expect(prefs.getLastPatchCheckAt(), 0, reason: '没检查就不该落时间戳');
    });

    testWidgets('节流窗口内 → 拦在闸门外，且不覆盖原时间戳', (tester) async {
      final stamp =
          DateTime.now().millisecondsSinceEpoch -
          const Duration(minutes: 5).inMilliseconds;
      await prefs.setLastPatchCheckAt(stamp);

      final shown = await _runMaybeShow(tester, prefs, manual: false);

      expect(shown, isFalse);
      expect(_CountingGithubProxy.reads, 0, reason: '节流窗口内不应读任何配置');
      expect(prefs.getLastPatchCheckAt(), stamp);
    });

    testWidgets('时间戳落在未来（设备时钟被往回调过）→ 仍放行，并自愈时间戳', (tester) async {
      // 用户把设备时钟从 2030 调回当下：旧时间戳成了未来值。若按 elapsed < 窗口
      // 判断就会一直被节流到真实时间追上去（可能几个月），且节流分支不重写时间戳、
      // 自己好不了 —— 自动检查等于静默失效。
      final future =
          DateTime.now().millisecondsSinceEpoch +
          const Duration(days: 365).inMilliseconds;
      await prefs.setLastPatchCheckAt(future);

      final shown = await _runMaybeShow(tester, prefs, manual: false);

      expect(shown, isFalse);
      expect(_CountingGithubProxy.reads, 1, reason: '未来时间戳不该把检查挡死');
      expect(
        prefs.getLastPatchCheckAt(),
        lessThan(future),
        reason: '应重写为当前时间，自愈这个坏时间戳',
      );
    });

    testWidgets('节流窗口外 → 重新放行', (tester) async {
      final stale =
          DateTime.now().millisecondsSinceEpoch -
          (kPatchCheckThrottle + const Duration(minutes: 1)).inMilliseconds;
      await prefs.setLastPatchCheckAt(stale);

      final shown = await _runMaybeShow(tester, prefs, manual: false);

      expect(shown, isFalse);
      expect(_CountingGithubProxy.reads, 1);
      expect(prefs.getLastPatchCheckAt(), greaterThan(stale));
    });
  });

  group('设置页手动检查（manual: true）', () {
    testWidgets('同时无视开关与节流，且不动节流时间戳', (tester) async {
      // 两道闸都设成「会拦住自动检查」的状态
      await prefs.setAutoUpdateCheckEnabled(false);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await prefs.setLastPatchCheckAt(stamp);

      final shown = await _runMaybeShow(tester, prefs, manual: true);

      expect(shown, isFalse, reason: '测试平台非 Android，无补丁可弹');
      expect(_CountingGithubProxy.reads, 1, reason: '手动检查必须绕过两道闸真的去查');
      expect(prefs.getLastPatchCheckAt(), stamp, reason: '手动检查不该重置启动节流窗口');
    });
  });
}
