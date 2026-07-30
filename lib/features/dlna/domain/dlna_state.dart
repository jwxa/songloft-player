class DlnaDeviceInfo {
  final String id;
  final String name;
  final String location;

  const DlnaDeviceInfo({
    required this.id,
    required this.name,
    required this.location,
  });
}

class DlnaState {
  final List<DlnaDeviceInfo> devices;
  final DlnaDeviceInfo? activeDevice;
  final bool isDiscovering;
  final bool isCasting;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final String? error;

  const DlnaState({
    this.devices = const [],
    this.activeDevice,
    this.isDiscovering = false,
    this.isCasting = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.error,
  });

  DlnaState copyWith({
    List<DlnaDeviceInfo>? devices,
    DlnaDeviceInfo? Function()? activeDevice,
    bool? isDiscovering,
    bool? isCasting,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    String? Function()? error,
  }) {
    return DlnaState(
      devices: devices ?? this.devices,
      activeDevice: activeDevice != null ? activeDevice() : this.activeDevice,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      isCasting: isCasting ?? this.isCasting,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      error: error != null ? error() : this.error,
    );
  }
}
