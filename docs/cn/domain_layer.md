# Domain 层架构

> 本文档描述 Songloft Player 的纯 Dart Domain 层设计。Domain 层将核心业务逻辑从 Flutter/Riverpod 表现层中剥离，实现独立单元测试和清晰的关注点分离。

---

## 设计原则

1. **零 Flutter 依赖** — domain 目录内所有文件仅 import `dart:*` 和 `shared/models/*`
2. **薄 Notifier** — 表现层 Notifier 退化为调度层（接收 UI 事件 → 调用 domain → 更新 state → 驱动平台 API）
3. **可测试性** — 所有 domain use case 可用 `dart test` 直接测试，无需 WidgetTester
4. **渐进式** — 每个 use case 独立提取，不破坏现有功能

---

## 目录结构

```
lib/features/player/domain/
├── player_state.dart               # PlayerState、PlayMode、SleepTimerStatus
├── playback_context.dart           # PlaybackContext（队列来源标识）
├── playback_source.dart            # PlaybackSource 枚举
├── lyric_parser.dart               # LRC 歌词解析（纯 Dart）
├── equalizer_setting.dart          # 均衡器预设
├── play_history_entry.dart         # 播放历史条目
├── mini_player_controls.dart       # 迷你播放器控件配置
└── use_cases/
    ├── play_queue.dart             # 不可变播放队列值对象
    ├── play_mode_resolver.dart     # 播放模式 + next/prev 计算
    ├── playback_retry_policy.dart  # 重试策略（指数退避）
    ├── song_completion_router.dart # 歌曲播完 → 动作路由
    ├── sleep_timer_logic.dart      # 睡眠定时逻辑
    ├── queue_loader.dart           # 后台队列分批加载
    └── prefetch_strategy.dart      # 预加载决策

lib/features/library/domain/
├── repositories/
│   └── songs_repository_interface.dart   # ISongsRepository 抽象
└── use_cases/
    └── favorite_service.dart             # 收藏管理逻辑

lib/features/playlist/domain/
├── playlist.dart                         # Playlist 模型
├── repositories/
│   └── playlist_repository_interface.dart # IPlaylistRepository 抽象
└── use_cases/
    ├── playlist_sort.dart                # 排序算法（支持自定义比较器）
    └── pinyin_comparator.dart            # 拼音比较器适配器
```

---

## Use Cases 概览

### PlayQueue

不可变值对象，封装播放队列的增删改查操作并正确维护 `currentIndex`。

| 方法 | 职责 |
|------|------|
| `add(songs)` | 追加去重 (by id+type) |
| `insert(pos, song)` | 指定位置插入，调整 index |
| `removeAt(index)` | 删除并返回是否需要停止播放 |
| `move(old, new)` | 拖拽排序，跟踪当前歌曲 |

### PlayModeResolver

有状态类，维护随机播放已播历史，根据 5 种模式计算 next/prev index。

- 随机模式：不重复直到全部播完再重置（保留当前避免立即重复）
- 预选机制：`preSelectNext()` 缓存下一首 index 供 prefetch 使用

### PlaybackRetryPolicy

封装重试决策：本地歌曲 2 次/1s 固定，网络歌曲 7 次/指数退避(2s base, 10s cap)。
连续 3 首失败强制停止。

### SongCompletionRouter

纯函数：`PlayMode × 队列位置 → CompletionAction`（重播/暂停/下一首/停止）。

### SleepTimerLogic

管理两种互斥的睡眠模式（按时长倒计时 / 按歌曲数倒数），封装 Timer 生命周期。

### QueueLoader

分批加载 + generation-based 竞态取消 + 环形拼装（从目标位置旋转队列）。支持 3 次重试。

### PrefetchStrategy

预加载决策：评估是否需要预热下一首（排除本地歌/single 模式/空列表），late-stage 保险触发（剩余 < 30s）。

### FavoriteService

收藏歌单查找/创建 + 分页 ID 加载 + toggle，通过函数式依赖注入解耦网络层。

### PlaylistSort

排序算法（按名称/按数字前缀），支持注入自定义 `compareStrings` 比较器实现 locale-aware 排序。
已有序检测（返回 null 免无效 API 调用）。

---

## 测试

```bash
# 运行所有 domain 层测试（209 个）
flutter test test/features/player/domain/use_cases/ \
             test/features/playlist/domain/use_cases/ \
             test/features/library/domain/use_cases/

# 验证 domain 层无 Flutter 依赖
grep -r "package:flutter" lib/features/*/domain/use_cases/ && echo "FAIL" || echo "PASS"
```

---

## 扩展指南

添加新 use case 的步骤：

1. 在对应 feature 的 `domain/use_cases/` 下创建纯 Dart 文件
2. 确保仅 import `dart:*` 和 `shared/models/*`
3. 在 `test/features/<feature>/domain/use_cases/` 下创建测试
4. 修改 Notifier 委托调用新 use case
5. 验证：`dart analyze` + `flutter test`
