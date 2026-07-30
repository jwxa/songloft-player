import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

typedef PositionProvider = Duration Function();

typedef DurationProvider = Duration Function();

class HomeWidgetService {
  static final HomeWidgetService _instance = HomeWidgetService._();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._();

  static const String _androidWidgetName = 'SongloftNowPlayingWidgetProvider';
  static const String _iosWidgetKind = 'SongloftNowPlayingWidget';

  static const String _keyTitle = 'widget_song_title';
  static const String _keyArtist = 'widget_song_artist';
  static const String _keyArtUrl = 'widget_song_art_url';
  static const String _keyIsPlaying = 'widget_is_playing';
  static const String _keyHasSong = 'widget_has_song';
  static const String _keyIsFavorite = 'widget_is_favorite';
  static const String _keyPosition = 'widget_position';
  static const String _keyDuration = 'widget_duration';

  bool _initialized = false;
  Timer? _progressTimer;

  bool get _isApplicable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_isApplicable || _initialized) return;
    try {
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId('group.com.songloft.songloftFlutter');
      }
      _initialized = true;
      debugPrint('[HomeWidget] initialized');
    } catch (e) {
      debugPrint('[HomeWidget] init failed: $e');
    }
  }

  Future<void> updateNowPlaying({
    required String title,
    required String artist,
    String? artUrl,
    required bool isPlaying,
    bool isFavorite = false,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    if (!_isApplicable) return;
    try {
      await HomeWidget.saveWidgetData(_keyTitle, title);
      await HomeWidget.saveWidgetData(_keyArtist, artist);
      await HomeWidget.saveWidgetData(_keyArtUrl, artUrl ?? '');
      await HomeWidget.saveWidgetData(_keyIsPlaying, isPlaying);
      await HomeWidget.saveWidgetData(_keyIsFavorite, isFavorite);
      await HomeWidget.saveWidgetData(_keyPosition, position.inMilliseconds);
      await HomeWidget.saveWidgetData(_keyDuration, duration.inMilliseconds);
      await HomeWidget.saveWidgetData(_keyHasSong, true);
      await _triggerUpdate();
      debugPrint(
        '[HomeWidget] updateNowPlaying: $title - $artist, playing=$isPlaying, fav=$isFavorite, pos=${position.inSeconds}s, dur=${duration.inSeconds}s',
      );
    } catch (e) {
      debugPrint('[HomeWidget] updateNowPlaying failed: $e');
    }
  }

  Future<void> updatePlaybackState(bool isPlaying) async {
    if (!_isApplicable) return;
    try {
      await HomeWidget.saveWidgetData(_keyIsPlaying, isPlaying);
      await _triggerUpdate();
      debugPrint('[HomeWidget] updatePlaybackState: playing=$isPlaying');
    } catch (e) {
      debugPrint('[HomeWidget] updatePlaybackState failed: $e');
    }
  }

  Future<void> updateFavoriteState(bool isFavorite) async {
    if (!_isApplicable) return;
    try {
      await HomeWidget.saveWidgetData(_keyIsFavorite, isFavorite);
      await _triggerUpdate();
      debugPrint('[HomeWidget] updateFavoriteState: fav=$isFavorite');
    } catch (e) {
      debugPrint('[HomeWidget] updateFavoriteState failed: $e');
    }
  }

  void startProgressUpdates({
    required PositionProvider currentPosition,
    required DurationProvider currentDuration,
  }) {
    if (!_isApplicable) return;
    stopProgressUpdates();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = currentPosition();
        final dur = currentDuration();
        await HomeWidget.saveWidgetData(_keyPosition, pos.inMilliseconds);
        await HomeWidget.saveWidgetData(_keyDuration, dur.inMilliseconds);
        await _triggerUpdate();
      } catch (e) {
        debugPrint('[HomeWidget] progress update failed: $e');
      }
    });
  }

  void stopProgressUpdates() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> clearNowPlaying() async {
    if (!_isApplicable) return;
    try {
      await HomeWidget.saveWidgetData(_keyTitle, '');
      await HomeWidget.saveWidgetData(_keyArtist, '');
      await HomeWidget.saveWidgetData(_keyArtUrl, '');
      await HomeWidget.saveWidgetData(_keyIsPlaying, false);
      await HomeWidget.saveWidgetData(_keyHasSong, false);
      await HomeWidget.saveWidgetData(_keyIsFavorite, false);
      await HomeWidget.saveWidgetData(_keyPosition, 0);
      await HomeWidget.saveWidgetData(_keyDuration, 0);
      stopProgressUpdates();
      await _triggerUpdate();
      debugPrint('[HomeWidget] clearNowPlaying');
    } catch (e) {
      debugPrint('[HomeWidget] clearNowPlaying failed: $e');
    }
  }

  Future<void> _triggerUpdate() async {
    if (Platform.isAndroid) {
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } else if (Platform.isIOS) {
      await HomeWidget.updateWidget(iOSName: _iosWidgetKind);
    }
  }
}
