import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/home/domain/home_grid_config.dart';

void main() {
  group('HomeGridConfig.fromStorage', () {
    test('未设置过任何值时回落默认（自动列数 + 2 行）', () {
      final config = HomeGridConfig.fromStorage(columns: null, rows: null);
      expect(config, HomeGridConfig.defaults);
      expect(config.isAutoColumns, isTrue);
      expect(config.rows, HomeGridConfig.defaultRows);
    });

    test('非法值（手改 prefs / 版本回退）回落默认而不是抛', () {
      final config = HomeGridConfig.fromStorage(columns: 7, rows: 99);
      expect(config, HomeGridConfig.defaults);
    });

    test('合法值原样读回', () {
      final config = HomeGridConfig.fromStorage(columns: 5, rows: 3);
      expect(config.columns, 5);
      expect(config.rows, 3);
    });

    test('哨兵值合法：0 列 = 自动，0 行 = 全部', () {
      final config = HomeGridConfig.fromStorage(columns: 0, rows: 0);
      expect(config.isAutoColumns, isTrue);
      expect(config.isAllRows, isTrue);
    });
  });

  group('HomeGridConfig.resolveColumns', () {
    test('自动档采用调用方按断点算出的值', () {
      expect(const HomeGridConfig().resolveColumns(4), 4);
      expect(const HomeGridConfig().resolveColumns(3), 3);
    });

    test('显式列数忽略断点值', () {
      expect(const HomeGridConfig(columns: 5).resolveColumns(4), 5);
    });
  });

  group('HomeGridConfig.maxItems', () {
    test('有限行数 = 列 × 行', () {
      expect(const HomeGridConfig(columns: 5, rows: 3).maxItems(5), 15);
      expect(const HomeGridConfig(columns: 4, rows: 2).maxItems(4), 8);
    });

    test('全部行数返回 null（不截断）', () {
      expect(
        const HomeGridConfig(
          columns: 5,
          rows: HomeGridConfig.allRows,
        ).maxItems(5),
        isNull,
      );
    });

    test('按传入的有效列数算，而不是配置里的列数', () {
      // 用户选 6 列 2 行，但窄窗口 clamp 到 4 列 → 应为 8 项（2 行），不是 12
      const config = HomeGridConfig(columns: 6, rows: 2);
      expect(config.maxItems(4), 8);
    });
  });

  group('computeHomeGridMetrics', () {
    // 首页整体套着 ConstrainedBox(maxWidth: 1200)，减去左右各 AppSpacing.lg(24)
    const wideContentWidth = 1152.0;
    const spacing = 16.0;
    // AppSpacing.sm(8) + bodyMedium 行高(20) + bodySmall 行高(16)
    const textBlockHeight = 44.0;

    test('默认配置（4 列 @1200 上限）长宽比被夹回改造前的 0.82 —— 零视觉 diff', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: wideContentWidth,
        requestedColumns: 4,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 4);
      expect(metrics.childAspectRatio, kHomeGridMaxAspectRatio);
      expect(metrics.columnsClamped, isFalse);
    });

    test('宽度充足时不 clamp，6 列照给', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: wideContentWidth,
        requestedColumns: 6,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 6);
      expect(metrics.columnsClamped, isFalse);
      // 6 列时卡片变窄，长宽比应低于上限（封面才能占满宽）
      expect(metrics.childAspectRatio, lessThan(kHomeGridMaxAspectRatio));
    });

    // 4 列需要 4*120 + 3*16 = 528px，511 放不下 → 只能 3 列
    test('平板竖屏（内容宽 511）选 6 列被 clamp 到 3 列', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: 511,
        requestedColumns: 6,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 3);
      expect(metrics.columnsClamped, isTrue);
    });

    test('桌面临界（内容宽 611）选 6 列被 clamp 到 4 列', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: 611,
        requestedColumns: 6,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 4);
      expect(metrics.columnsClamped, isTrue);
    });

    test('内容宽 811 足够放下 6 列', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: 811,
        requestedColumns: 6,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 6);
    });

    test('每张卡片都不窄于 minCardWidth', () {
      for (final width in <double>[300, 511, 611, 811, 1152]) {
        final metrics = computeHomeGridMetrics(
          availableWidth: width,
          requestedColumns: 6,
          spacing: spacing,
          textBlockHeight: textBlockHeight,
        );
        expect(
          metrics.cardWidth,
          greaterThanOrEqualTo(kHomeGridMinCardWidth),
          reason: 'availableWidth=$width',
        );
      }
    });

    test('极窄宽度收敛到 1 列，且不产生 NaN / 负数', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: 60,
        requestedColumns: 6,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 1);
      expect(metrics.cardWidth, 60);
      expect(metrics.childAspectRatio.isFinite, isTrue);
      expect(metrics.childAspectRatio, greaterThan(0));
    });

    test('宽度为 0（首帧 / 折叠容器）不抛且长宽比有限', () {
      final metrics = computeHomeGridMetrics(
        availableWidth: 0,
        requestedColumns: 4,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      expect(metrics.columns, 1);
      expect(metrics.childAspectRatio, kHomeGridMaxAspectRatio);
    });

    test('长宽比恒在 [下限, 上限] 区间内', () {
      for (final width in <double>[0, 60, 300, 511, 811, 1152, 3000]) {
        for (final columns in <int>[1, 3, 4, 5, 6]) {
          final ratio =
              computeHomeGridMetrics(
                availableWidth: width,
                requestedColumns: columns,
                spacing: spacing,
                textBlockHeight: textBlockHeight,
              ).childAspectRatio;
          expect(ratio, greaterThanOrEqualTo(kHomeGridMinAspectRatio));
          expect(ratio, lessThanOrEqualTo(kHomeGridMaxAspectRatio));
        }
      }
    });

    test('系统大字号（文字块变高）时长宽比变小，让封面让位而不是挤压文字', () {
      final normal = computeHomeGridMetrics(
        availableWidth: 811,
        requestedColumns: 5,
        spacing: spacing,
        textBlockHeight: textBlockHeight,
      );
      final scaled = computeHomeGridMetrics(
        availableWidth: 811,
        requestedColumns: 5,
        spacing: spacing,
        textBlockHeight: textBlockHeight * 2,
      );
      expect(scaled.childAspectRatio, lessThan(normal.childAspectRatio));
    });
  });
}
