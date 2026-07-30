import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/utils/audio_format_helper.dart';

void main() {
  group('needsNativeVideoHls', () {
    test('老旧容器命中黑名单', () {
      for (final ext in [
        'mpg',
        'mpeg',
        'vob',
        'rmvb',
        'rm',
        'wmv',
        'asf',
        'avi',
        'flv',
        'ts',
        'm2ts',
        'mts',
      ]) {
        expect(
          AudioFormatHelper.needsNativeVideoHls(ext, null),
          isTrue,
          reason: ext,
        );
        expect(
          AudioFormatHelper.needsNativeVideoHls(null, 'music/video.$ext'),
          isTrue,
          reason: ext,
        );
      }
    });

    test('现代容器直出不命中', () {
      for (final ext in ['mp4', 'mkv', 'webm', 'mov', 'm4v', '3gp']) {
        expect(
          AudioFormatHelper.needsNativeVideoHls(ext, null),
          isFalse,
          reason: ext,
        );
      }
    });

    test('filePath 扩展名优先于 format', () {
      expect(
        AudioFormatHelper.needsNativeVideoHls('mp4', 'music/video.mpg'),
        isTrue,
      );
      expect(
        AudioFormatHelper.needsNativeVideoHls('mpg', 'music/video.mp4'),
        isFalse,
      );
    });

    test('大小写不敏感', () {
      expect(AudioFormatHelper.needsNativeVideoHls('MPG', null), isTrue);
      expect(
        AudioFormatHelper.needsNativeVideoHls(null, 'music/VIDEO.RMVB'),
        isTrue,
      );
    });

    test('null/空/未知格式默认直出', () {
      expect(AudioFormatHelper.needsNativeVideoHls(null, null), isFalse);
      expect(AudioFormatHelper.needsNativeVideoHls('', null), isFalse);
      expect(AudioFormatHelper.needsNativeVideoHls('xyz', null), isFalse);
      // filePath 无扩展名时回落 format
      expect(AudioFormatHelper.needsNativeVideoHls('mpg', 'noext'), isTrue);
    });
  });

  group('isWebCompatibleVideo（重构后行为不变）', () {
    test('mp4/webm/mov 兼容', () {
      expect(AudioFormatHelper.isWebCompatibleVideo('mp4', null), isTrue);
      expect(AudioFormatHelper.isWebCompatibleVideo('webm', null), isTrue);
      expect(AudioFormatHelper.isWebCompatibleVideo('mov', null), isTrue);
    });

    test('其他格式不兼容，filePath 优先', () {
      expect(AudioFormatHelper.isWebCompatibleVideo('mkv', null), isFalse);
      expect(AudioFormatHelper.isWebCompatibleVideo('mkv', 'a/b.mp4'), isTrue);
      expect(AudioFormatHelper.isWebCompatibleVideo(null, null), isFalse);
    });
  });
}
