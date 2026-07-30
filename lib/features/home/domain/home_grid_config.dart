/// 首页宽屏歌单网格的行列配置（songloft-org/songloft#332）。
///
/// 仅作用于首页宽屏（`context.useWideLayout`）的「我的歌单 / 我的电台」两个网格；
/// 窄屏走 `PlaylistCarousel` 横向轮播，没有行列概念。曲库的
/// `browse_collection_view` 不受此配置影响。
///
/// 纯本地偏好，刻意不参与服务器偏好同步：网格规格与屏幕尺寸强相关，同一账号的
/// 手机与桌面不该共享同一份配置。
class HomeGridConfig {
  /// 每行列数；[autoColumns] 表示沿用响应式断点（平板 3 / 桌面 4）。
  final int columns;

  /// 显示行数；[allRows] 表示不截断。
  final int rows;

  const HomeGridConfig({this.columns = autoColumns, this.rows = defaultRows});

  /// 「自动」哨兵：不写死列数，交给 responsive 断点决定。
  static const int autoColumns = 0;

  /// 「全部」哨兵：不按行数截断。
  static const int allRows = 0;

  /// 默认 2 行 —— 与改造前硬编码的 `crossAxisCount * 2` 行为一致。
  static const int defaultRows = 2;

  /// 设置页可选列数（数组顺序即 UI 顺序）。
  /// 没有 2：`autoColumns` 在 mobile 断点解析为 2，但 mobile 走轮播取不到网格。
  static const List<int> columnOptions = <int>[autoColumns, 3, 4, 5, 6];

  /// 设置页可选行数（数组顺序即 UI 顺序）。
  static const List<int> rowOptions = <int>[1, 2, 3, 4, allRows];

  static const HomeGridConfig defaults = HomeGridConfig();

  bool get isAutoColumns => columns == autoColumns;
  bool get isAllRows => rows == allRows;

  /// 把「自动」哨兵解析成真实列数；[autoValue] 由调用方按响应式断点算出。
  int resolveColumns(int autoValue) => isAutoColumns ? autoValue : columns;

  /// 本次最多渲染多少张卡片，返回 null 表示不截断。
  ///
  /// [effectiveColumns] 必须传**已按可用宽度 clamp 后**的列数（见
  /// [computeHomeGridMetrics]），否则「6 列 2 行」在窄窗口降到 4 列时会渲染
  /// 12 项 = 3 行，行数语义就漂了。
  int? maxItems(int effectiveColumns) =>
      isAllRows ? null : effectiveColumns * rows;

  HomeGridConfig copyWith({int? columns, int? rows}) =>
      HomeGridConfig(columns: columns ?? this.columns, rows: rows ?? this.rows);

  /// 读盘校正：null（从未设置）与非法值（手改 prefs / 未来版本回退）一律回落
  /// 默认，绝不抛。默认值只在本类定义一处。
  static HomeGridConfig fromStorage({int? columns, int? rows}) =>
      HomeGridConfig(
        columns:
            (columns != null && columnOptions.contains(columns))
                ? columns
                : autoColumns,
        rows: (rows != null && rowOptions.contains(rows)) ? rows : defaultRows,
      );

  @override
  bool operator ==(Object other) =>
      other is HomeGridConfig && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => 'HomeGridConfig(columns: $columns, rows: $rows)';
}

/// 选了「不限行数」时，首页会自动续拉后续分页把歌单补齐；这是累积条数的硬上限。
///
/// 首页单次请求只拿 `PaginatedPlaylistsNotifier.pageLimit`（30）条，不续拉的话
/// 「不限」其实只有 30 个。但也不能无脑拉到底 —— 歌单上千的用户进首页会连打几十个
/// 请求。折中：续拉到本上限为止，超出的部分靠区域标题的「查看全部」入口去曲库看。
/// 设置页的摘要文案直接引用本常量，改这里文案自动跟上。
const int kHomeAutoLoadAllMaxItems = 200;

/// 卡片最小宽度。低于此值歌单名会被压成两三个字 + 省略号，信息量归零；
/// 用户在窄窗口里选了 6 列时靠它兜底。量级对齐 `jsplugin_grid.dart` 里那套
/// 按宽度算列的既有范式。
const double kHomeGridMinCardWidth = 120;

/// 卡片长宽比上限 = 改造前的字面值。1200px 上限 + 4 列时按面积算出的比例
/// （≈0.86）会被夹回 0.82，保证默认配置的视觉与改造前一致。
const double kHomeGridMaxAspectRatio = 0.82;

/// 卡片长宽比下限：极窄卡片时兜底，避免高度失控。
const double kHomeGridMinAspectRatio = 0.45;

/// 网格几何：clamp 后的列数、单卡宽度、长宽比。
class HomeGridMetrics {
  final int columns;
  final double cardWidth;
  final double childAspectRatio;

  /// 用户选的列数被可用宽度压下来了。
  final bool columnsClamped;

  const HomeGridMetrics({
    required this.columns,
    required this.cardWidth,
    required this.childAspectRatio,
    required this.columnsClamped,
  });
}

/// 纯函数：由**真实可用宽度**算出网格几何。
///
/// [availableWidth] 务必来自 `LayoutBuilder`，不要用 `context.screenWidth`：
/// 宽屏下左侧有 NavigationRail(~81) 或侧边栏(241)，外层还套着
/// `ConstrainedBox(maxWidth: 1200)`，屏幕宽度会大幅高估网格宽度。
///
/// - 列数按 [minCardWidth] 收敛：n 列需要 `n*min + (n-1)*spacing <= width`，
///   反解得 `n <= (width + spacing) / (min + spacing)`。
/// - 长宽比让封面正好是「满宽正方形」：卡片高 = 宽 + 文字块高，故
///   `ratio = w / (w + textBlockHeight)`，再夹到 [kHomeGridMaxAspectRatio]。
///   不夹的话列数一多，封面（`Expanded` 里的 `AspectRatio(1)`）会自行缩成
///   letterbox 并靠左，卡片右侧留出难看的空隙。
HomeGridMetrics computeHomeGridMetrics({
  required double availableWidth,
  required int requestedColumns,
  required double spacing,
  required double textBlockHeight,
  double minCardWidth = kHomeGridMinCardWidth,
}) {
  final fit = ((availableWidth + spacing) / (minCardWidth + spacing)).floor();
  final columns = requestedColumns.clamp(1, fit < 1 ? 1 : fit);
  final cardWidth = (availableWidth - spacing * (columns - 1)) / columns;
  final ratio =
      cardWidth <= 0
          ? kHomeGridMaxAspectRatio
          : (cardWidth / (cardWidth + textBlockHeight))
              .clamp(kHomeGridMinAspectRatio, kHomeGridMaxAspectRatio)
              .toDouble();
  return HomeGridMetrics(
    columns: columns,
    cardWidth: cardWidth,
    childAspectRatio: ratio,
    columnsClamped: columns < requestedColumns,
  );
}
