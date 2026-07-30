/// 当前歌曲的播放来源。用于播放页「歌曲信息」区分本地缓存 vs 远端流串。
enum PlaybackSource {
  /// 本机手动缓存的文件（`file://`）。
  localCache,

  /// 远端流串（走 `/api/v1/songs/{id}/play`，含 just_audio 临时边播边缓存）。
  remoteStream,

  /// 尚未确定（未开始播放）。
  unknown,
}
