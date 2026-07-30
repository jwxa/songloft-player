import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/library/domain/use_cases/favorite_service.dart';

void main() {
  late FavoriteService service;

  setUp(() {
    service = FavoriteService();
  });

  group('FavoriteService', () {
    group('initialization', () {
      test('playlistId is null before initialization', () {
        expect(service.isInitialized, isFalse);
        expect(service.playlistId, isNull);
      });

      test('initializes successfully with playlistId and loaded IDs', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 42,
          loadSongIds: (playlistId) async => {1, 2, 3},
        );

        expect(service.isInitialized, isTrue);
        expect(service.playlistId, 42);
        expect(service.favoriteIds, {1, 2, 3});
      });

      test('loaded IDs can be queried via isFavorite', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 10,
          loadSongIds: (playlistId) async => {100, 200, 300},
        );

        expect(service.isFavorite(100), isTrue);
        expect(service.isFavorite(200), isTrue);
        expect(service.isFavorite(300), isTrue);
        expect(service.isFavorite(999), isFalse);
      });

      test('is idempotent — second call is a no-op', () async {
        int callCount = 0;
        await service.initialize(
          findOrCreatePlaylist: () async {
            callCount++;
            return 1;
          },
          loadSongIds: (id) async => {10},
        );

        await service.initialize(
          findOrCreatePlaylist: () async {
            callCount++;
            return 2;
          },
          loadSongIds: (id) async => {20},
        );

        expect(callCount, 1);
        expect(service.playlistId, 1);
        expect(service.favoriteIds, {10});
      });

      test('throws and remains uninitialized when findOrCreatePlaylist fails',
          () async {
        expect(
          () => service.initialize(
            findOrCreatePlaylist: () async => throw Exception('network error'),
            loadSongIds: (id) async => {},
          ),
          throwsException,
        );

        // Service should remain uninitialized after failure
        await Future.delayed(Duration.zero);
        expect(service.isInitialized, isFalse);
        expect(service.playlistId, isNull);
      });

      test('throws and remains uninitialized when loadSongIds fails', () async {
        expect(
          () => service.initialize(
            findOrCreatePlaylist: () async => 5,
            loadSongIds: (id) async => throw Exception('load error'),
          ),
          throwsException,
        );

        await Future.delayed(Duration.zero);
        expect(service.isInitialized, isFalse);
      });

      test('can retry initialization after failure', () async {
        // First attempt fails
        try {
          await service.initialize(
            findOrCreatePlaylist: () async => throw Exception('fail'),
            loadSongIds: (id) async => {},
          );
        } catch (_) {}

        // Second attempt succeeds
        await service.initialize(
          findOrCreatePlaylist: () async => 99,
          loadSongIds: (id) async => {7, 8, 9},
        );

        expect(service.isInitialized, isTrue);
        expect(service.playlistId, 99);
        expect(service.favoriteIds, {7, 8, 9});
      });
    });

    group('isFavorite', () {
      test('returns false when not initialized', () {
        expect(service.isFavorite(1), isFalse);
        expect(service.isFavorite(999), isFalse);
      });

      test('returns false for non-favorited song after initialization',
          () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 1,
          loadSongIds: (id) async => {10, 20},
        );

        expect(service.isFavorite(30), isFalse);
      });
    });

    group('toggle', () {
      test('adds a song when not currently favorited', () async {
        int? addedPlaylistId;
        int? addedSongId;

        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {},
        );

        final result = await service.toggle(
          songId: 42,
          addSong: (playlistId, songId) async {
            addedPlaylistId = playlistId;
            addedSongId = songId;
          },
          removeSong: (playlistId, songId) async {
            fail('removeSong should not be called');
          },
        );

        expect(result, isTrue);
        expect(service.isFavorite(42), isTrue);
        expect(addedPlaylistId, 5);
        expect(addedSongId, 42);
      });

      test('removes a song when currently favorited', () async {
        int? removedPlaylistId;
        int? removedSongId;

        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {42, 100},
        );

        final result = await service.toggle(
          songId: 42,
          addSong: (playlistId, songId) async {
            fail('addSong should not be called');
          },
          removeSong: (playlistId, songId) async {
            removedPlaylistId = playlistId;
            removedSongId = songId;
          },
        );

        expect(result, isFalse);
        expect(service.isFavorite(42), isFalse);
        expect(removedPlaylistId, 5);
        expect(removedSongId, 42);
      });

      test('throws StateError when not initialized', () async {
        expect(
          () => service.toggle(
            songId: 1,
            addSong: (pid, sid) async {},
            removeSong: (pid, sid) async {},
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('does not modify local set when addSong throws', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {},
        );

        try {
          await service.toggle(
            songId: 42,
            addSong: (pid, sid) async => throw Exception('network'),
            removeSong: (pid, sid) async {},
          );
        } catch (_) {}

        expect(service.isFavorite(42), isFalse);
      });

      test('does not modify local set when removeSong throws', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {42},
        );

        try {
          await service.toggle(
            songId: 42,
            addSong: (pid, sid) async {},
            removeSong: (pid, sid) async => throw Exception('network'),
          );
        } catch (_) {}

        expect(service.isFavorite(42), isTrue);
      });
    });

    group('refresh', () {
      test('reloads IDs from backend', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {1, 2, 3},
        );

        await service.refresh(loadSongIds: (id) async => {4, 5, 6});

        expect(service.favoriteIds, {4, 5, 6});
        expect(service.isFavorite(1), isFalse);
        expect(service.isFavorite(4), isTrue);
      });

      test('throws StateError when not initialized', () {
        expect(
          () => service.refresh(loadSongIds: (id) async => {}),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('reset', () {
      test('clears all state', () async {
        await service.initialize(
          findOrCreatePlaylist: () async => 5,
          loadSongIds: (id) async => {1, 2, 3},
        );

        service.reset();

        expect(service.isInitialized, isFalse);
        expect(service.playlistId, isNull);
        expect(service.favoriteIds, isEmpty);
        expect(service.isFavorite(1), isFalse);
      });
    });
  });
}
