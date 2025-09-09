/// Stub implementation used on non-web platforms.
/// This file is conditionally replaced by `web_local_recorder_web.dart` on web builds.
library;

import 'dart:typed_data';

class WebRecordedData {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  const WebRecordedData({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}

class WebLocalRecorder {
  bool get isSupported => false;

  Future<void> start() async {
    throw UnsupportedError('WebLocalRecorder is only supported on web');
  }

  Future<WebRecordedData> stop() async {
    throw UnsupportedError('WebLocalRecorder is only supported on web');
  }

  Future<void> saveToDisk(WebRecordedData data) async {
    throw UnsupportedError('WebLocalRecorder is only supported on web');
  }
}
