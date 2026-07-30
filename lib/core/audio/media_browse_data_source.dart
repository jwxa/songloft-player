import '../../features/library/data/songs_api.dart';
import '../../features/playlist/data/playlist_api.dart';
import '../../features/playlist/domain/playlist.dart';
import '../../shared/models/song.dart';

abstract class MediaBrowseDataSource {
  Future<List<Song>> getRecentSongs({int limit = 50});
  Future<List<Song>> getFavoriteSongs({int limit = 100});
  Future<List<Playlist>> getPlaylists();
  Future<List<Song>> getPlaylistSongs(int playlistId, {int limit = 100});
  Future<List<Song>> getAllSongs({int limit = 200});
  Future<Song?> getSongById(int id);
  Future<List<Song>> searchSongs(String query, {int limit = 20});
}

class ApiMediaBrowseDataSource implements MediaBrowseDataSource {
  final SongsApi _songsApi;
  final PlaylistApi _playlistApi;

  ApiMediaBrowseDataSource({
    required SongsApi songsApi,
    required PlaylistApi playlistApi,
  }) : _songsApi = songsApi,
       _playlistApi = playlistApi;

  @override
  Future<List<Song>> getRecentSongs({int limit = 50}) async {
    final response = await _songsApi.getSongs(limit: limit);
    return response.songs;
  }

  @override
  Future<List<Song>> getFavoriteSongs({int limit = 100}) async {
    // id=1 is the built-in favorites playlist
    final response = await _playlistApi.getPlaylistSongs(1, limit: limit);
    return response.songs;
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    final response = await _playlistApi.getPlaylists(limit: 100);
    return response.playlists;
  }

  @override
  Future<List<Song>> getPlaylistSongs(int playlistId, {int limit = 100}) async {
    final response = await _playlistApi.getPlaylistSongs(
      playlistId,
      limit: limit,
    );
    return response.songs;
  }

  @override
  Future<List<Song>> getAllSongs({int limit = 200}) async {
    final response = await _songsApi.getSongs(limit: limit);
    return response.songs;
  }

  @override
  Future<Song?> getSongById(int id) async {
    try {
      return await _songsApi.getSong(id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    final response = await _songsApi.getSongs(keyword: query, limit: limit);
    return response.songs;
  }
}
