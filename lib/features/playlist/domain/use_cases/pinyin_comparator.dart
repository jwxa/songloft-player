/// 中文拼音排序比较器适配器。
///
/// 本文件定义了拼音比较器的类型签名和工厂模式，供 [PlaylistSort] 注入使用。
/// domain 层不引入具体拼音库依赖，具体实现由上层（presentation/infrastructure）提供。
///
/// ## 使用方式
///
/// 1. 在 `pubspec.yaml` 中添加拼音库依赖：
///    ```yaml
///    dependencies:
///      lpinyin: ^2.0.3
///    ```
///
/// 2. 在 presentation 层或 shared 层创建具体实现：
///    ```dart
///    import 'package:lpinyin/lpinyin.dart';
///    import 'package:songloft_flutter/features/playlist/domain/use_cases/pinyin_comparator.dart';
///
///    /// 基于 lpinyin 库的中文拼音比较器实现。
///    int lpinyinCompare(String a, String b) {
///      final pinyinA = PinyinHelper.getPinyin(a, separator: '');
///      final pinyinB = PinyinHelper.getPinyin(b, separator: '');
///      return pinyinA.toLowerCase().compareTo(pinyinB.toLowerCase());
///    }
///    ```
///
/// 3. 在 UI 层注入比较器：
///    ```dart
///    final sorter = PlaylistSort(compareStrings: lpinyinCompare);
///    sorter.sortSongsByName(songs);
///    ```
///
/// ## 设计说明
///
/// - domain 层仅定义 [StringComparator] 类型别名，不引入外部依赖
/// - 具体拼音库（lpinyin、pinyin 等）的选择和初始化由上层负责
/// - 支持任意 locale-aware 排序策略（拼音、笔画、注音等），只需实现相同签名即可
library;

/// 字符串比较器函数签名。
///
/// 符合 [Comparator<String>] 契约：
/// - 返回负数表示 [a] 排在 [b] 前面
/// - 返回 0 表示相等
/// - 返回正数表示 [a] 排在 [b] 后面
typedef StringComparator = int Function(String a, String b);

/// 创建一个带有回退机制的拼音比较器包装。
///
/// [pinyinConvert] 将字符串转换为拼音（或其他 sortable 形式），
/// 转换失败时回退到原始字符串的大小写不敏感比较。
///
/// 示例：
/// ```dart
/// final compare = createPinyinComparator(
///   (s) => PinyinHelper.getPinyin(s, separator: ''),
/// );
/// final sorter = PlaylistSort(compareStrings: compare);
/// ```
StringComparator createPinyinComparator(String Function(String) pinyinConvert) {
  return (String a, String b) {
    final convertedA = pinyinConvert(a);
    final convertedB = pinyinConvert(b);
    return convertedA.toLowerCase().compareTo(convertedB.toLowerCase());
  };
}
