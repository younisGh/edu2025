// Web implementation: calls window.agoraBridge JS functions
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

class ScreenShareBridge {
  bool _inited = false;
  Future<void> init({
    required String appId,
    required String channel,
    required int uidScreen,
    required String tokenScreen,
  }) async {
    final bridge = js_util.getProperty(html.window, 'agoraBridge');
    if (bridge == null) {
      throw StateError('agoraBridge not found on window');
    }
    await js_util.promiseToFuture(
      js_util.callMethod(bridge, 'initScreenClient', [
        js_util.jsify({
          'appId': appId,
          'channel': channel,
          'uidScreen': uidScreen,
          'tokenScreen': tokenScreen,
        }),
      ]),
    );
    _inited = true;
  }

  Future<void> start() async {
    if (!_inited) {
      throw StateError('ScreenShareBridge.start() called before init().');
    }
    final bridge = js_util.getProperty(html.window, 'agoraBridge');
    if (bridge == null) throw StateError('agoraBridge not found');
    await js_util.promiseToFuture(
      js_util.callMethod(bridge, 'startScreenShare', []),
    );
  }

  Future<void> stop() async {
    if (!_inited) {
      throw StateError('ScreenShareBridge.stop() called before init().');
    }
    final bridge = js_util.getProperty(html.window, 'agoraBridge');
    if (bridge == null) throw StateError('agoraBridge not found');
    await js_util.promiseToFuture(
      js_util.callMethod(bridge, 'stopScreenShare', []),
    );
  }
}
