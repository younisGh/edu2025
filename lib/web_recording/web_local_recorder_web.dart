// Web-only implementation using dart:html MediaRecorder
// This file is selected at compile-time via conditional import from the stub.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'dart:js_util' as js_util;

class WebRecordedData {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  const WebRecordedData({required this.bytes, required this.mimeType, required this.fileName});
}

class WebLocalRecorder {
  html.MediaRecorder? _recorder;
  List<html.Blob> _chunks = <html.Blob>[];
  html.MediaStream? _stream;

  bool get isSupported =>
      html.MediaRecorder.isTypeSupported('video/webm;codecs=vp9') ||
      html.MediaRecorder.isTypeSupported('video/webm');

  Future<void> start() async {
    // Request a fresh camera+mic stream
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw StateError('mediaDevices not available');
    }
    _stream = await mediaDevices.getUserMedia({
      'audio': true,
      'video': {'width': 1280, 'height': 720}
    });

    String mimeType = 'video/webm;codecs=vp9';
    if (!html.MediaRecorder.isTypeSupported(mimeType)) {
      mimeType = 'video/webm';
    }

    _chunks = <html.Blob>[];
    _recorder = html.MediaRecorder(_stream!, {'mimeType': mimeType});
    // Listen for dataavailable
    _recorder!.addEventListener('dataavailable', (html.Event e) {
      try {
        final data = js_util.getProperty(e, 'data');
        if (data != null && data is html.Blob) {
          _chunks.add(data);
        }
      } catch (_) {}
    });
    final completer = Completer<void>();
    _recorder!.addEventListener('start', (_) => completer.complete());
    _recorder!.start(1000); // timeslice (ms)
    return completer.future;
  }

  Future<WebRecordedData> stop() async {
    if (_recorder == null) {
      throw StateError('Recorder not started');
    }
    final stopCompleter = Completer<WebRecordedData>();
    _recorder!.addEventListener('stop', (_) async {
      try {
        final blob = html.Blob(_chunks, _recorder!.mimeType ?? 'video/webm');
        final reader = html.FileReader();
        final done = Completer<Uint8List>();
        reader.onLoadEnd.listen((_) {
          final result = reader.result;
          if (result is ByteBuffer) {
            done.complete(Uint8List.view(result));
          } else if (result is Uint8List) {
            done.complete(result);
          } else if (result is List<int>) {
            done.complete(Uint8List.fromList(result));
          } else {
            done.completeError(StateError('Unexpected FileReader.result type: ${result.runtimeType}'));
          }
        });
        reader.readAsArrayBuffer(blob);
        final bytes = await done.future;
        final fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}.webm';
        stopCompleter.complete(WebRecordedData(bytes: bytes, mimeType: blob.type, fileName: fileName));
      } catch (e) {
        stopCompleter.completeError(e);
      } finally {
        _chunks.clear();
        _stream?.getTracks().forEach((t) => t.stop());
        _stream = null;
      }
    });
    _recorder!.stop();
    return stopCompleter.future;
  }

  Future<void> saveToDisk(WebRecordedData data) async {
    final blob = html.Blob([data.bytes], data.mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)
      ..download = data.fileName
      ..style.display = 'none';
    html.document.body!.children.add(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }
}
