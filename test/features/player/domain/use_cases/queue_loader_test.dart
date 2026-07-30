import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/use_cases/queue_loader.dart';
import 'package:songloft_flutter/shared/models/song.dart';

Song _makeSong(int id) => Song(
  id: id,
  type: 'local',
  title: 'Song $id',
  duration: 180.0,
  addedAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('QueueLoader', () {
    late QueueLoader loader;

    setUp(() {
      loader = QueueLoader();
    });

    group('invalidate', () {
      test('increments generation', () {
        expect(loader.generation, 0);
        final g1 = loader.invalidate();
        expect(g1, 1);
        expect(loader.generation, 1);
        final g2 = loader.invalidate();
        expect(g2, 2);
      });

      test('isSuperseded returns true for old generation', () {
        final g = loader.generation;
        loader.invalidate();
        expect(loader.isSuperseded(g), isTrue);
      });

      test('isSuperseded returns false for current generation', () {
        final g = loader.invalidate();
        expect(loader.isSuperseded(g), isFalse);
      });
    });

    group('loadRemaining', () {
      test('normal batched load (250 songs, pageSize=100 -> 3 batches)', () async {
        final allSongs = List.generate(250, (i) => _makeSong(i));
        final batches = <List<Song>>[];
        int fetchCount = 0;

        final result = await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 250,
          alreadyLoaded: 0,
          pageSize: 100,
          fetch: (offset, limit) async {
            fetchCount++;
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) => batches.add(songs),
        );

        expect(result, isTrue);
        expect(fetchCount, 3);
        expect(batches.length, 3);
        expect(batches[0].length, 100);
        expect(batches[1].length, 100);
        expect(batches[2].length, 50);
        // Verify order
        expect(batches[0].first.id, 0);
        expect(batches[1].first.id, 100);
        expect(batches[2].first.id, 200);
      });

      test('generation cancellation stops loading mid-way', () async {
        final allSongs = List.generate(300, (i) => _makeSong(i));
        final batches = <List<Song>>[];
        int fetchCount = 0;
        final gen = loader.generation;

        final result = await loader.loadRemaining(
          generation: gen,
          totalCount: 300,
          alreadyLoaded: 0,
          pageSize: 100,
          fetch: (offset, limit) async {
            fetchCount++;
            // Invalidate after first fetch returns
            if (fetchCount == 1) {
              loader.invalidate();
            }
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) => batches.add(songs),
        );

        // After first fetch, generation is invalidated. The check after fetch
        // detects superseded and returns false.
        expect(result, isFalse);
        expect(fetchCount, 1);
        expect(batches.length, 0); // onBatch not called because superseded after fetch
      });

      test('generation cancellation before fetch stops immediately', () async {
        final gen = loader.generation;
        loader.invalidate(); // Supersede immediately
        int fetchCount = 0;

        final result = await loader.loadRemaining(
          generation: gen,
          totalCount: 100,
          alreadyLoaded: 0,
          fetch: (offset, limit) async {
            fetchCount++;
            return [];
          },
          onBatch: (_) {},
        );

        expect(result, isFalse);
        expect(fetchCount, 0);
      });

      test('empty batch stops loading early', () async {
        int fetchCount = 0;
        final batches = <List<Song>>[];

        final result = await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 300,
          alreadyLoaded: 0,
          pageSize: 100,
          fetch: (offset, limit) async {
            fetchCount++;
            // Return empty on second fetch
            if (offset >= 100) return [];
            return List.generate(100, (i) => _makeSong(offset + i));
          },
          onBatch: (songs) => batches.add(songs),
        );

        expect(result, isTrue);
        expect(fetchCount, 2);
        expect(batches.length, 1); // Only first batch had data
      });

      test('fetch exception causes failure after retries exhausted', () async {
        int fetchCount = 0;

        final result = await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 200,
          alreadyLoaded: 0,
          pageSize: 100,
          maxRetries: 2,
          fetch: (offset, limit) async {
            fetchCount++;
            throw Exception('network error');
          },
          onBatch: (_) {},
        );

        // Should retry maxRetries times then return false
        expect(result, isFalse);
        expect(fetchCount, 2); // maxRetries = 2
      });

      test('fetch retries on failure then succeeds', () async {
        int fetchCount = 0;
        final batches = <List<Song>>[];

        final result = await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 50,
          alreadyLoaded: 0,
          pageSize: 100,
          maxRetries: 3,
          fetch: (offset, limit) async {
            fetchCount++;
            // Fail on first attempt, succeed on second
            if (fetchCount == 1) throw Exception('transient');
            return List.generate(50, (i) => _makeSong(i));
          },
          onBatch: (songs) => batches.add(songs),
        );

        expect(result, isTrue);
        expect(fetchCount, 2);
        expect(batches.length, 1);
        expect(batches[0].length, 50);
      });

      test('onBatch called in order after each batch', () async {
        final allSongs = List.generate(150, (i) => _makeSong(i));
        final batchIds = <int>[];

        await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 150,
          alreadyLoaded: 0,
          pageSize: 50,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) => batchIds.add(songs.first.id),
        );

        expect(batchIds, [0, 50, 100]);
      });

      test('alreadyLoaded starts from correct offset', () async {
        final allSongs = List.generate(200, (i) => _makeSong(i));
        final batches = <List<Song>>[];

        await loader.loadRemaining(
          generation: loader.generation,
          totalCount: 200,
          alreadyLoaded: 150,
          pageSize: 100,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) => batches.add(songs),
        );

        expect(batches.length, 1);
        expect(batches[0].first.id, 150);
        expect(batches[0].length, 50);
      });
    });

    group('loadAroundSong', () {
      test('ring load: targetIndex=5, totalCount=10', () async {
        final allSongs = List.generate(10, (i) => _makeSong(i));
        final loadedIds = <int>[];

        final result = await loader.loadAroundSong(
          generation: loader.generation,
          targetIndex: 5,
          totalCount: 10,
          pageSize: 100,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) {
            for (final s in songs) {
              loadedIds.add(s.id);
            }
          },
        );

        expect(result, isTrue);
        // Should load 6,7,8,9 (tail) then 0,1,2,3,4 (head)
        expect(loadedIds, [6, 7, 8, 9, 0, 1, 2, 3, 4]);
      });

      test('ring load with batched fetching', () async {
        final allSongs = List.generate(20, (i) => _makeSong(i));
        final batches = <List<int>>[];

        await loader.loadAroundSong(
          generation: loader.generation,
          targetIndex: 10,
          totalCount: 20,
          pageSize: 4,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) => batches.add(songs.map((s) => s.id).toList()),
        );

        // Tail: 11..19 fetched in batches of 4: [11,12,13,14], [15,16,17,18], [19]
        // Head: 0..9 fetched in batches of 4: [0,1,2,3], [4,5,6,7], [8,9]
        expect(batches[0], [11, 12, 13, 14]);
        expect(batches[1], [15, 16, 17, 18]);
        expect(batches[2], [19]);
        expect(batches[3], [0, 1, 2, 3]);
        expect(batches[4], [4, 5, 6, 7]);
        expect(batches[5], [8, 9]);
      });

      test('targetIndex < 0: loads entire range', () async {
        final allSongs = List.generate(5, (i) => _makeSong(i));
        final loadedIds = <int>[];

        final result = await loader.loadAroundSong(
          generation: loader.generation,
          targetIndex: -1,
          totalCount: 5,
          pageSize: 100,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) {
            for (final s in songs) {
              loadedIds.add(s.id);
            }
          },
        );

        expect(result, isTrue);
        expect(loadedIds, [0, 1, 2, 3, 4]);
      });

      test('targetIndex=0: loads only tail (1..end)', () async {
        final allSongs = List.generate(5, (i) => _makeSong(i));
        final loadedIds = <int>[];

        await loader.loadAroundSong(
          generation: loader.generation,
          targetIndex: 0,
          totalCount: 5,
          pageSize: 100,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) {
            for (final s in songs) {
              loadedIds.add(s.id);
            }
          },
        );

        // Head range [0, 0) is empty, only tail [1,5) is loaded
        expect(loadedIds, [1, 2, 3, 4]);
      });

      test('targetIndex=last: loads only head (0..last-1)', () async {
        final allSongs = List.generate(5, (i) => _makeSong(i));
        final loadedIds = <int>[];

        await loader.loadAroundSong(
          generation: loader.generation,
          targetIndex: 4,
          totalCount: 5,
          pageSize: 100,
          fetch: (offset, limit) async {
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) {
            for (final s in songs) {
              loadedIds.add(s.id);
            }
          },
        );

        // Tail range [5, 5) is empty, only head [0, 4) is loaded
        expect(loadedIds, [0, 1, 2, 3]);
      });

      test('cancellation during tail stops before head', () async {
        final allSongs = List.generate(10, (i) => _makeSong(i));
        final loadedIds = <int>[];
        final gen = loader.generation;

        final result = await loader.loadAroundSong(
          generation: gen,
          targetIndex: 5,
          totalCount: 10,
          pageSize: 2,
          fetch: (offset, limit) async {
            // Invalidate after first fetch of tail
            if (offset == 6) {
              loader.invalidate();
            }
            final end = (offset + limit).clamp(0, allSongs.length);
            return allSongs.sublist(offset, end);
          },
          onBatch: (songs) {
            for (final s in songs) {
              loadedIds.add(s.id);
            }
          },
        );

        expect(result, isFalse);
        // First batch [6,7] loaded, then fetch at offset=8 detects cancel after
        // fetch(6,2) triggered invalidate — the check after that fetch sees superseded.
        // Actually: fetch(6,2) invalidates, returns [6,7], then isSuperseded check
        // after fetch returns true -> no onBatch called for that batch.
        // Let me reconsider: offset starts at 6 (targetIndex+1). limit = clamp(10-6, 1, 2) = 2.
        // fetch(6, 2) is called, invalidate() happens, returns [6,7].
        // After fetch: isSuperseded(gen) -> true, returns false.
        expect(loadedIds, isEmpty);
      });
    });
  });
}
