import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/playlist/domain/use_cases/playlist_sort.dart';
import 'package:songloft_flutter/shared/models/song.dart';
import 'package:songloft_flutter/features/playlist/domain/playlist.dart';

Song _song(int id, String title) => Song(
  id: id,
  type: 'local',
  title: title,
  duration: 180.0,
  addedAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

Playlist _playlist(int id, String name) => Playlist(
  id: id,
  type: 'normal',
  name: name,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

void main() {
  group('extractLeadingNumber', () {
    test('extracts number from beginning', () {
      expect(extractLeadingNumber('03. 歌名'), 3);
    });

    test('returns null when no number present', () {
      expect(extractLeadingNumber('歌名'), null);
    });

    test('extracts number followed by letters', () {
      expect(extractLeadingNumber('12abc'), 12);
    });

    test('extracts first number when multiple present', () {
      expect(extractLeadingNumber('01. Track 02'), 1);
    });

    test('handles number in the middle', () {
      expect(extractLeadingNumber('干得漂亮 | 01 好意被辜负'), 1);
    });

    test('returns null for empty string', () {
      expect(extractLeadingNumber(''), null);
    });
  });

  group('PlaylistSort', () {
    late PlaylistSort sorter;

    setUp(() {
      sorter = PlaylistSort();
    });

    group('sortSongsByName', () {
      test('sorts ascending by default', () {
        final songs = [
          _song(1, 'Cherry'),
          _song(2, 'Apple'),
          _song(3, 'Banana'),
        ];

        final result = sorter.sortSongsByName(songs);

        expect(result, [2, 3, 1]); // Apple, Banana, Cherry
      });

      test('sorts descending when specified', () {
        final songs = [
          _song(1, 'Apple'),
          _song(2, 'Cherry'),
          _song(3, 'Banana'),
        ];

        final result = sorter.sortSongsByName(songs, ascending: false);

        expect(result, [2, 3, 1]); // Cherry, Banana, Apple
      });

      test('returns null when already sorted ascending', () {
        final songs = [
          _song(1, 'Apple'),
          _song(2, 'Banana'),
          _song(3, 'Cherry'),
        ];

        final result = sorter.sortSongsByName(songs);

        expect(result, isNull);
      });

      test('returns null when already sorted descending', () {
        final songs = [
          _song(1, 'Cherry'),
          _song(2, 'Banana'),
          _song(3, 'Apple'),
        ];

        final result = sorter.sortSongsByName(songs, ascending: false);

        expect(result, isNull);
      });

      test('case insensitive comparison', () {
        final songs = [
          _song(1, 'banana'),
          _song(2, 'Apple'),
          _song(3, 'cherry'),
        ];

        final result = sorter.sortSongsByName(songs);

        expect(result, [2, 1, 3]); // Apple, banana, cherry
      });

      test('returns null for empty list', () {
        final result = sorter.sortSongsByName([]);
        expect(result, isNull);
      });

      test('returns null for single item', () {
        final result = sorter.sortSongsByName([_song(1, 'Only')]);
        expect(result, isNull);
      });
    });

    group('sortSongsByNumberPrefix', () {
      test('sorts by number prefix', () {
        final songs = [
          _song(1, '03. Third'),
          _song(2, '01. First'),
          _song(3, '02. Second'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 3, 1]);
      });

      test('songs with numbers come before songs without', () {
        final songs = [
          _song(1, 'No number here'),
          _song(2, '01. Has number'),
          _song(3, 'Another without'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 3, 1]); // 01.Has number, Another without, No number here
      });

      test('mixed with and without number prefix', () {
        final songs = [
          _song(1, 'Zebra'),
          _song(2, '02. Second'),
          _song(3, 'Apple'),
          _song(4, '01. First'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        // Numbers first (01, 02), then alphabetical (Apple, Zebra)
        expect(result, [4, 2, 3, 1]);
      });

      test('same number prefix sorted by name', () {
        final songs = [
          _song(1, '01. Banana'),
          _song(2, '01. Apple'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 1]); // 01. Apple, 01. Banana
      });

      test('returns null when already sorted', () {
        final songs = [
          _song(1, '01. First'),
          _song(2, '02. Second'),
          _song(3, 'Zebra'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        expect(result, isNull);
      });

      test('no-number songs sorted alphabetically among themselves', () {
        final songs = [
          _song(1, 'Zebra'),
          _song(2, 'Apple'),
          _song(3, 'Mango'),
        ];

        final result = sorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 3, 1]); // Apple, Mango, Zebra
      });
    });

    group('sortPlaylistsByName', () {
      test('sorts ascending', () {
        final playlists = [
          _playlist(1, 'Rock'),
          _playlist(2, 'Jazz'),
          _playlist(3, 'Pop'),
        ];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]); // Jazz, Pop, Rock
      });

      test('sorts descending', () {
        final playlists = [
          _playlist(1, 'Jazz'),
          _playlist(2, 'Rock'),
          _playlist(3, 'Pop'),
        ];

        final result = sorter.sortPlaylistsByName(playlists, ascending: false);

        expect(result, [2, 3, 1]); // Rock, Pop, Jazz
      });

      test('returns null when already sorted', () {
        final playlists = [
          _playlist(1, 'Apple'),
          _playlist(2, 'Banana'),
          _playlist(3, 'Cherry'),
        ];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, isNull);
      });

      test('case insensitive', () {
        final playlists = [
          _playlist(1, 'banana'),
          _playlist(2, 'Apple'),
        ];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, [2, 1]);
      });
    });

    group('sortPlaylistsByNumberPrefix', () {
      test('sorts by number prefix', () {
        final playlists = [
          _playlist(1, '03. Third'),
          _playlist(2, '01. First'),
          _playlist(3, '02. Second'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, [2, 3, 1]);
      });

      test('playlists with numbers before those without', () {
        final playlists = [
          _playlist(1, 'No Number'),
          _playlist(2, '01. Has Number'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, [2, 1]);
      });

      test('returns null when already sorted', () {
        final playlists = [
          _playlist(1, '01. First'),
          _playlist(2, '02. Second'),
          _playlist(3, 'Zebra'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, isNull);
      });
    });

    group('custom compareStrings', () {
      test('custom comparator is used for sortSongsByName', () {
        // 使用反转比较器：Z 排在 A 前面
        final reverseSorter = PlaylistSort(
          compareStrings: (a, b) => b.toLowerCase().compareTo(a.toLowerCase()),
        );

        final songs = [
          _song(1, 'Apple'),
          _song(2, 'Cherry'),
          _song(3, 'Banana'),
        ];

        // 反转序：Cherry, Banana, Apple
        final result = reverseSorter.sortSongsByName(songs);

        expect(result, [2, 3, 1]);
      });

      test('custom comparator is used for sortPlaylistsByName', () {
        // 按字符串长度排序
        final lengthSorter = PlaylistSort(
          compareStrings: (a, b) => a.length.compareTo(b.length),
        );

        final playlists = [
          _playlist(1, 'Long Name Here'),
          _playlist(2, 'Hi'),
          _playlist(3, 'Medium'),
        ];

        // 按长度：Hi(2), Medium(6), Long Name Here(14)
        final result = lengthSorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]);
      });

      test('custom comparator is used for number prefix fallback', () {
        // 当数字前缀相同时，应使用自定义比较器
        final reverseSorter = PlaylistSort(
          compareStrings: (a, b) => b.toLowerCase().compareTo(a.toLowerCase()),
        );

        final songs = [
          _song(1, '01. Apple'),
          _song(2, '01. Cherry'),
        ];

        // 数字相同，反转序：01. Cherry, 01. Apple
        final result = reverseSorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 1]);
      });

      test('custom comparator does not affect number comparison', () {
        // 自定义比较器不会影响数字前缀的数值比较
        final reverseSorter = PlaylistSort(
          compareStrings: (a, b) => b.toLowerCase().compareTo(a.toLowerCase()),
        );

        final songs = [
          _song(1, '03. Third'),
          _song(2, '01. First'),
          _song(3, '02. Second'),
        ];

        // 数字排序仍然是 01, 02, 03（数值比较不受字符串比较器影响）
        final result = reverseSorter.sortSongsByNumberPrefix(songs);

        expect(result, [2, 3, 1]);
      });

      test('default comparator produces stable behavior for Chinese characters', () {
        // 文档化：默认比较器对中文字符使用 Unicode code point 顺序
        // 这不是拼音序，但行为是确定且一致的
        final songs = [
          _song(1, '爱'),   // Unicode: U+7231
          _song(2, '不'),   // Unicode: U+4E0D
          _song(3, '从'),   // Unicode: U+4ECE
        ];

        final result = sorter.sortSongsByName(songs);

        // Unicode code point 顺序：不(4E0D) < 从(4ECE) < 爱(7231)
        expect(result, [2, 3, 1]);
      });

      test('pinyin comparator sorts Chinese by pinyin order', () {
        // 模拟拼音比较器：提供一个简单的映射表
        final pinyinMap = {
          '爱': 'ai',
          '不': 'bu',
          '从': 'cong',
          '大': 'da',
          '风': 'feng',
          '歌': 'ge',
        };

        String toPinyin(String s) {
          // 简单实现：逐字转换（单字符中文映射）
          final buffer = StringBuffer();
          for (var i = 0; i < s.length; i++) {
            final char = s[i];
            buffer.write(pinyinMap[char] ?? char);
          }
          return buffer.toString();
        }

        final pinyinSorter = PlaylistSort(
          compareStrings: (a, b) =>
              toPinyin(a).toLowerCase().compareTo(toPinyin(b).toLowerCase()),
        );

        final songs = [
          _song(1, '风'),   // feng
          _song(2, '爱'),   // ai
          _song(3, '大'),   // da
          _song(4, '不'),   // bu
        ];

        // 拼音序：爱(ai) < 不(bu) < 大(da) < 风(feng)
        final result = pinyinSorter.sortSongsByName(songs);

        expect(result, [2, 4, 3, 1]);
      });

      test('pinyin comparator works with mixed Chinese and English', () {
        final pinyinMap = {
          '我': 'wo',
          '的': 'de',
          '歌': 'ge',
        };

        String toPinyin(String s) {
          final buffer = StringBuffer();
          for (var i = 0; i < s.length; i++) {
            final char = s[i];
            buffer.write(pinyinMap[char] ?? char);
          }
          return buffer.toString();
        }

        final pinyinSorter = PlaylistSort(
          compareStrings: (a, b) =>
              toPinyin(a).toLowerCase().compareTo(toPinyin(b).toLowerCase()),
        );

        final playlists = [
          _playlist(1, '我的歌'),    // wodege
          _playlist(2, 'Apple'),     // apple
          _playlist(3, '歌'),        // ge
        ];

        // 拼音序：Apple(apple) < 歌(ge) < 我的歌(wodege)
        final result = pinyinSorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]);
      });
    });
  });
}
