# Domain Layer Architecture

> This document describes the pure-Dart Domain layer of Songloft Player. The Domain layer decouples core business logic from the Flutter/Riverpod presentation layer, enabling independent unit testing and clear separation of concerns.

---

## Design Principles

1. **Zero Flutter dependencies** — all files under `domain/` only import `dart:*` and `shared/models/*`
2. **Thin Notifiers** — presentation-layer Notifiers become orchestrators (receive UI events → call domain → update state → drive platform APIs)
3. **Testability** — all domain use cases are testable with plain `dart test`, no WidgetTester required
4. **Incremental** — each use case is extracted independently without breaking existing functionality

---

## Directory Structure

```
lib/features/player/domain/
├── player_state.dart               # PlayerState, PlayMode, SleepTimerStatus
├── playback_context.dart           # PlaybackContext (queue origin identifier)
├── playback_source.dart            # PlaybackSource enum
├── lyric_parser.dart               # LRC lyric parsing (pure Dart)
├── equalizer_setting.dart          # Equalizer presets
├── play_history_entry.dart         # Play history entry
├── mini_player_controls.dart       # Mini player controls config
└── use_cases/
    ├── play_queue.dart             # Immutable play queue value object
    ├── play_mode_resolver.dart     # Play mode + next/prev index calculation
    ├── playback_retry_policy.dart  # Retry policy (exponential backoff)
    ├── song_completion_router.dart # Song completed → action router
    ├── sleep_timer_logic.dart      # Sleep timer logic
    ├── queue_loader.dart           # Background queue batch loading
    └── prefetch_strategy.dart      # Prefetch decision logic

lib/features/library/domain/
├── repositories/
│   └── songs_repository_interface.dart   # ISongsRepository abstract
└── use_cases/
    └── favorite_service.dart             # Favorite management logic

lib/features/playlist/domain/
├── playlist.dart                         # Playlist model
├── repositories/
│   └── playlist_repository_interface.dart # IPlaylistRepository abstract
└── use_cases/
    ├── playlist_sort.dart                # Sort algorithms (custom comparator support)
    └── pinyin_comparator.dart            # Pinyin comparator adapter
```

---

## Use Cases Overview

### PlayQueue
Immutable value object encapsulating queue add/insert/remove/move with correct `currentIndex` tracking.

### PlayModeResolver
Stateful class maintaining shuffle history, computing next/prev index for 5 play modes.
Random mode: no-repeat until exhausted, then reset (preserving current to avoid immediate repeat).

### PlaybackRetryPolicy
Retry decisions: local songs 2 retries/1s fixed, network songs 7 retries/exponential backoff (2s base, 10s cap).
3 consecutive failures → force stop.

### SongCompletionRouter
Pure function: `PlayMode × queue position → CompletionAction` (replay/pause/next/stop).

### SleepTimerLogic
Manages two mutually exclusive sleep modes (duration countdown / after-N-songs), encapsulates Timer lifecycle.

### QueueLoader
Batched loading + generation-based race cancellation + ring assembly. Supports 3 retries per batch.

### PrefetchStrategy
Prefetch decisions: evaluate whether to warm next song (excludes local/single-mode/empty), late-stage insurance (remaining < 30s).

### FavoriteService
Favorite playlist find-or-create + paginated ID loading + toggle, decoupled from network via function injection.

### PlaylistSort
Sort algorithms (by name / by number prefix), supports injected `compareStrings` comparator for locale-aware sorting.
Already-sorted detection (returns null to skip unnecessary API calls).

---

## Testing

```bash
# Run all domain layer tests (209 tests)
flutter test test/features/player/domain/use_cases/ \
             test/features/playlist/domain/use_cases/ \
             test/features/library/domain/use_cases/

# Verify domain layer has no Flutter dependencies
grep -r "package:flutter" lib/features/*/domain/use_cases/ && echo "FAIL" || echo "PASS"
```

---

## Extension Guide

Steps to add a new use case:

1. Create a pure Dart file under the feature's `domain/use_cases/`
2. Ensure it only imports `dart:*` and `shared/models/*`
3. Create tests under `test/features/<feature>/domain/use_cases/`
4. Modify the Notifier to delegate to the new use case
5. Verify: `dart analyze` + `flutter test`
