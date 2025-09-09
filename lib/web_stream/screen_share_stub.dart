/// Stub bridge for screen sharing on non-web platforms.
class ScreenShareBridge {
  Future<void> init({required String appId, required String channel, required int uidScreen, required String tokenScreen}) async {
    throw UnsupportedError('ScreenShareBridge is only supported on web');
  }

  Future<void> start() async {
    throw UnsupportedError('ScreenShareBridge is only supported on web');
  }

  Future<void> stop() async {
    throw UnsupportedError('ScreenShareBridge is only supported on web');
  }
}
