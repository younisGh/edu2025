import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt_flutter;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt_iframe;

class VideoPlayerPage extends StatefulWidget {
  final String title;
  final String videoUrl;

  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.videoUrl,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  yt_flutter.YoutubePlayerController? _ytController; // mobile/desktop
  yt_iframe.YoutubePlayerController? _ytIframeController; // web
  bool _isError = false;
  bool _isYouTube = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _isYouTube = _detectYouTube(widget.videoUrl);
      if (_isYouTube) {
        final vid = _extractYouTubeId(widget.videoUrl);
        if (vid == null || vid.isEmpty) {
          throw Exception('Invalid YouTube URL');
        }
        final isLive = _isYouTubeLiveUrl(widget.videoUrl);
        if (kIsWeb) {
          _ytIframeController = yt_iframe.YoutubePlayerController.fromVideoId(
            videoId: vid,
            autoPlay: false, // disable autoplay on web to avoid restrictions
            params: const yt_iframe.YoutubePlayerParams(
              showFullscreenButton: true,
            ),
          );
        } else {
          _ytController = yt_flutter.YoutubePlayerController(
            initialVideoId: vid,
            flags: const yt_flutter.YoutubePlayerFlags(
              autoPlay: true,
              showLiveFullscreenButton: true,
              forceHD: false,
              enableCaption: true,
            ),
          );
          if (isLive) {
            _ytController?.dispose();
            _ytController = yt_flutter.YoutubePlayerController(
              initialVideoId: vid,
              flags: const yt_flutter.YoutubePlayerFlags(
                autoPlay: true,
                showLiveFullscreenButton: true,
                forceHD: false,
                enableCaption: true,
                isLive: true,
              ),
            );
          }
        }
        if (mounted) setState(() {});
      } else {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        await _videoController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
          allowPlaybackSpeedChanging: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: const Color(0xFFEA2A33),
            handleColor: const Color(0xFFEA2A33),
            bufferedColor: Colors.grey.shade400,
            backgroundColor: Colors.grey.shade300,
          ),
        );
        if (mounted) setState(() {});
      }
    } catch (_) {
      setState(() => _isError = true);
    }
  }

  bool _detectYouTube(String url) {
    final u = url.toLowerCase();
    return u.contains('youtube.com') || u.contains('youtu.be');
  }

  String? _extractYouTubeId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('youtu.be')) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) return segments.first;
      }
      if (uri.host.contains('youtube.com')) {
        final v = uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;
        // handle /live/VIDEO_ID
        final segments = uri.pathSegments;
        if (segments.isNotEmpty && segments.first == 'live' && segments.length > 1) {
          return segments[1];
        }
        // handle /embed/VIDEO_ID
        final embedIndex = segments.indexOf('embed');
        if (embedIndex != -1 && embedIndex + 1 < segments.length) {
          return segments[embedIndex + 1];
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isYouTubeLiveUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.host.contains('youtube.com')) return false;
      final segments = uri.pathSegments;
      return segments.isNotEmpty && segments.first == 'live' && segments.length > 1;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    try {
      if (kIsWeb) {
        // On web, avoid calling close() to prevent removeJavaScriptChannel error
        try {
          _ytIframeController?.stopVideo();
        } catch (_) {}
      } else {
        _ytController?.dispose();
      }
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title.isEmpty ? 'تشغيل الفيديو' : widget.title),
        ),
        body: Center(
          child: _isError
              ? const Text('تعذر تشغيل هذا الفيديو.')
              : _isYouTube
                  ? (kIsWeb
                      ? (_ytIframeController != null
                          ? yt_iframe.YoutubePlayer(
                              controller: _ytIframeController!,
                              aspectRatio: 16 / 9,
                            )
                          : const CircularProgressIndicator())
                      : (_ytController != null
                          ? AspectRatio(
                              aspectRatio: 16 / 9,
                              child: yt_flutter.YoutubePlayer(
                                controller: _ytController!,
                              ),
                            )
                          : const CircularProgressIndicator()))
                  : (_chewieController != null &&
                          _chewieController!
                              .videoPlayerController
                              .value
                              .isInitialized)
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio == 0
                              ? 16 / 9
                              : _videoController!.value.aspectRatio,
                          child: Chewie(controller: _chewieController!),
                        )
                      : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
