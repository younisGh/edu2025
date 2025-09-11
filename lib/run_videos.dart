import 'package:flutter/material.dart';
import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart'
    as yt_flutter;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:educational_platform/services/engagement_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:educational_platform/utils/typography.dart';

class RunVideosPage extends StatefulWidget {
  final String title;
  final String videoUrl;
  final String? description;

  const RunVideosPage({
    super.key,
    required this.title,
    required this.videoUrl,
    this.description,
  });

  @override
  State<RunVideosPage> createState() => _RunVideosPageState();
}

class _RunVideosPageState extends State<RunVideosPage> {
  // Video controllers
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  yt_flutter.YoutubePlayerController? _ytController;
  YoutubePlayerController? _ytIframeController;
  bool _isYouTube = false;
  bool _isError = false;
  late final String _videoKey;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _viewCounted = false;
  bool _isAdmin = false;
  String? _currentCategoryId;
  String? _currentCategoryName;
  Timer? _progressTimer;
  bool _markedCompleted = false;

  // Build initials from a user's name (supports single or multi-part names)
  String _initialsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'م';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final initials = (first + second).trim();
    return initials.isEmpty ? 'م' : initials;
  }

  Future<void> _resolveIsAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      final roleVal = (data?['role'] ?? '').toString();
      final isAdminVal = data?['isAdmin'] == true;
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdminVal || roleVal == 'Admin';
      });
    } catch (_) {}
  }

  Future<String?> _resolvePhotoUrl(String? url) async {
    try {
      if (url == null || url.isEmpty) return null;
      if (url.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(url);
        return await ref.getDownloadURL();
      }
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmDeleteComment(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التعليق'),
        content: const Text('هل أنت متأكد من حذف هذا التعليق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (_isAdmin) {
        await EngagementService.instance.adminDeleteComment(
          _videoKey,
          commentId,
        );
      } else {
        await EngagementService.instance.deleteComment(_videoKey, commentId);
      }
    }
  }

  Future<void> _openEditCommentSheet(
    String commentId,
    String initialText,
  ) async {
    final controller = TextEditingController(text: initialText);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final ctx = context; // capture bottom-sheet context
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تعديل التعليق',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب التعليق...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    await EngagementService.instance.updateComment(
                      _videoKey,
                      commentId,
                      text,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _videoKey = EngagementService.instance.videoKeyFromUrl(widget.videoUrl);
    EngagementService.instance.ensureVideoMeta(
      videoKey: _videoKey,
      title: widget.title,
      videoUrl: widget.videoUrl,
      description: widget.description,
    );
    // Increment views once when page opens
    _incrementViewsOnce();
    _initPlayer();
    _resolveIsAdmin();
    _resolveCurrentVideoCategory();
  }

  Future<void> _resolveCurrentVideoCategory() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('videos')
          .where('videoUrl', isEqualTo: widget.videoUrl)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) return;
      final data = qs.docs.first.data();
      final cid = (data['categoryId'] ?? '').toString();
      final cname = (data['category'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _currentCategoryId = cid.isNotEmpty ? cid : null;
        _currentCategoryName = cname.isNotEmpty ? cname : null;
      });
    } catch (_) {}
  }

  Future<void> _incrementViewsOnce() async {
    if (_viewCounted) return;
    _viewCounted = true;
    await EngagementService.instance.incrementViews(_videoKey);
  }

  Future<void> _initPlayer() async {
    try {
      _isYouTube = _detectYouTube(widget.videoUrl);
      if (_isYouTube) {
        final videoId = _extractYouTubeId(widget.videoUrl);
        if (videoId == null || videoId.isEmpty) {
          throw Exception('Invalid YouTube URL');
        }

        if (kIsWeb) {
          _ytIframeController = YoutubePlayerController.fromVideoId(
            videoId: videoId,
            autoPlay: true,
            params: const YoutubePlayerParams(showFullscreenButton: true),
          );
        } else {
          _ytController = yt_flutter.YoutubePlayerController(
            initialVideoId: videoId,
            flags: const yt_flutter.YoutubePlayerFlags(
              autoPlay: true,
              mute: false,
              isLive: false,
              forceHD: false,
              enableCaption: true,
            ),
          )..addListener(_ytPlayerListener);
        }
      } else {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        await _videoController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
        );
      }
      if (mounted) setState(() {});
      _startProgressTimer();
    } catch (_) {
      if (mounted) setState(() => _isError = true);
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // For YouTube, only track progress on non-web platforms.
        if (_isYouTube) {
          // For YouTube, only track progress on non-web platforms.
          if (kIsWeb) return; // Do not track YT progress on web

          if (_ytController == null || !_ytController!.value.isReady) return;
          final v = _ytController!.value;
          final posSec = v.position.inSeconds;
          final durSec = v.metaData.duration.inSeconds > 0
              ? v.metaData.duration.inSeconds
              : null;

          if (!_markedCompleted && posSec > 0) {
            await EngagementService.instance.updateWatchProgress(
              _videoKey,
              positionSec: posSec,
              durationSec: durSec,
            );
          }
        } else {
          // For other videos, track progress on all platforms.
          if (_videoController == null) return;
          final v = _videoController!.value;
          if (!v.isInitialized) return;
          final posSec = v.position.inSeconds;
          final durSec = v.duration.inSeconds > 0 ? v.duration.inSeconds : null;

          if (!_markedCompleted && posSec > 0) {
            await EngagementService.instance.updateWatchProgress(
              _videoKey,
              positionSec: posSec,
              durationSec: durSec,
            );
          }
        }
      } catch (_) {}
    });
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
        final segments = uri.pathSegments;
        final embedIndex = segments.indexOf('embed');
        if (embedIndex != -1 && embedIndex + 1 < segments.length) {
          return segments[embedIndex + 1];
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    // Save last known progress on dispose for non-YouTube videos
    try {
      if (!_isYouTube &&
          _videoController != null &&
          _videoController!.value.isInitialized) {
        final pos = _videoController!.value.position;
        final dur = _videoController!.value.duration;
        final posSec = pos.inSeconds;
        final durSec = dur.inSeconds > 0 ? dur.inSeconds : null;
        if (!_markedCompleted && posSec > 0) {
          EngagementService.instance.updateWatchProgress(
            _videoKey,
            positionSec: posSec,
            durationSec: durSec,
          );
        }
      }
    } catch (_) {}
    _chewieController?.dispose();
    _videoController?.dispose();
    _ytController?.dispose();
    _ytIframeController?.close();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(child: _buildVideoDetails()),
            SliverToBoxAdapter(child: _buildActionButtons()),
            _buildCommentsSection(),
            _buildRelatedVideosSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    // Top section shows the actual player

    return SliverAppBar(
      expandedHeight: 275.0,
      backgroundColor: const Color(0xFF1E293B),
      pinned: true,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Colors.black,
          child: Center(
            child: _isError
                ? Text(
                    'تعذر تشغيل هذا الفيديو.',
                    style: TextStyle(color: Colors.white, fontSize: sf(context, 14)),
                  )
                : _isYouTube
                ? kIsWeb
                      ? (_ytIframeController != null
                            ? YoutubePlayer(
                                controller: _ytIframeController!,
                                aspectRatio: 16 / 9,
                              )
                            : const CircularProgressIndicator())
                      : (_ytController != null)
                      ? yt_flutter.YoutubePlayer(
                          controller: _ytController!,
                          showVideoProgressIndicator: true,
                        )
                      : const CircularProgressIndicator()
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
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ),
      ],
    );
  }

  // Top controls removed since we show the real player

  Widget _buildVideoDetails() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title.isEmpty ? 'تشغيل الفيديو' : widget.title,
            style: TextStyle(
              fontSize: sf(context, 26),
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.description ?? 'وصف قصير وجذاب للفيديو.',
            style: TextStyle(
              fontSize: sf(context, 16),
              color: const Color(0xFF475569),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.remove_red_eye_outlined,
                size: 20,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              StreamBuilder<int>(
                stream: EngagementService.instance.viewsStream(_videoKey),
                builder: (context, snap) {
                  final views = snap.data ?? 0;
                  return Text(
                    '$views',
                    style: TextStyle(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: sf(context, 14),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Favorite toggle
          StreamBuilder<bool>(
            stream: EngagementService.instance.favoriteStream(_videoKey),
            builder: (context, snap) {
              final isFav = snap.data ?? false;
              return _buildActionButton(
                isFav ? Icons.favorite : Icons.favorite_outline,
                'تفضيل',
                Colors.pink,
                onTap: () =>
                    EngagementService.instance.toggleFavorite(_videoKey),
              );
            },
          ),
          // Comment add
          _buildActionButton(
            Icons.comment_outlined,
            'تعليق',
            Colors.blue,
            onTap: () => _openAddCommentSheet(),
          ),
          // Rating
          _buildActionButton(
            Icons.star_outline,
            'تقييم',
            Colors.amber,
            onTap: () => _openRatingSheet(),
          ),
          // PDF open if exists
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('video_meta')
                .doc(_videoKey)
                .snapshots(),
            builder: (context, snap) {
              final pdfUrl = (snap.data?.data()?['pdfUrl'] ?? '').toString();
              return _buildActionButton(
                Icons.picture_as_pdf_outlined,
                'PDF',
                Colors.green,
                onTap: () async {
                  if (pdfUrl.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('لا يوجد ملف PDF متاح لهذا الدرس'),
                      ),
                    );
                    return;
                  }
                  final uri = Uri.tryParse(pdfUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: sd(context, 28)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w600,
                fontSize: sf(context, 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Comments UI section
  Widget _buildCommentsSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التعليقات',
              style: TextStyle(
                fontSize: sf(context, 18),
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.commentsStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('لا توجد تعليقات بعد.'),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, i) {
                    final docSnap = docs[i];
                    final d = docSnap.data();
                    final isMine =
                        FirebaseAuth.instance.currentUser?.uid == d['userId'];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: FutureBuilder<String?>(
                        future: _resolvePhotoUrl(
                          (d['photoUrl'] ?? '').toString(),
                        ),
                        builder: (context, snap) {
                          final resolved = snap.data;
                          return CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.blueGrey.shade200,
                            backgroundImage:
                                (resolved != null && resolved.isNotEmpty)
                                ? NetworkImage(resolved)
                                : null,
                            child: (resolved == null || resolved.isEmpty)
                                ? Text(
                                    _initialsFromName(
                                      (d['name'] ?? 'مستخدم') as String,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                      title: Text(d['name'] ?? 'مستخدم'),
                      subtitle: Text(d['text'] ?? ''),
                      trailing: (isMine || _isAdmin)
                          ? PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await _openEditCommentSheet(
                                    docSnap.id,
                                    (d['text'] ?? '') as String,
                                  );
                                } else if (v == 'delete') {
                                  await _confirmDeleteComment(docSnap.id);
                                }
                              },
                              itemBuilder: (_) {
                                final items = <PopupMenuEntry<String>>[];
                                if (isMine) {
                                  items.add(
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل'),
                                    ),
                                  );
                                }
                                items.add(
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('حذف'),
                                  ),
                                );
                                return items;
                              },
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAddCommentSheet() {
    final ctx = context; // Capture local context
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أضف تعليقًا',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: sf(context, 16)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب تعليقك هنا...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = _commentCtrl.text.trim();
                    if (text.isEmpty) return;
                    await EngagementService.instance.addComment(
                      _videoKey,
                      text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx); // Use captured context
                    _commentCtrl.clear();
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('نشر'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openRatingSheet() {
    final ctx = context; // Capture local context
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        int selected = 0;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'قيّم هذا الدرس',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: sf(context, 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(5, (i) {
                      final idx = i + 1;
                      final filled = idx <= selected;
                      return IconButton(
                        onPressed: () => setStateSB(() => selected = idx),
                        icon: Icon(
                          filled ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StreamBuilder<double>(
                        stream: EngagementService.instance.averageRatingStream(
                          _videoKey,
                        ),
                        builder: (context, snap) {
                          final avg = snap.data ?? 0.0;
                          return Text(
                            'التقييم الحالي: ${avg.toStringAsFixed(1)}',
                          );
                        },
                      ),
                      StreamBuilder<int>(
                        stream: EngagementService.instance.ratingsCountStream(
                          _videoKey,
                        ),
                        builder: (context, snap) {
                          final count = snap.data ?? 0;
                          return Text('عدد المقيمين: $count');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selected == 0
                          ? null
                          : () async {
                              await EngagementService.instance.setRating(
                                _videoKey,
                                selected,
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx); // Use captured context
                              }
                            },
                      child: const Text('حفظ التقييم'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _ytPlayerListener() {
    if (_ytController == null) return;
    final v = _ytController!.value;
    // Mark completed for YouTube
    if (v.playerState == yt_flutter.PlayerState.ended) {
      if (!_markedCompleted) {
        _markedCompleted = true;
        EngagementService.instance.markCompleted(_videoKey);
      }
    }
    // Save progress on dispose (not on web for YouTube)
    if (!kIsWeb &&
        v.playerState == yt_flutter.PlayerState.paused &&
        v.position.inSeconds > 0) {
      final posSec = v.position.inSeconds;
      final durSec = v.metaData.duration.inSeconds > 0
          ? v.metaData.duration.inSeconds
          : null;
      if (!_markedCompleted) {
        EngagementService.instance.updateWatchProgress(
          _videoKey,
          positionSec: posSec,
          durationSec: durSec,
        );
      }
    }
  }

  Widget _buildRelatedVideosSection() {
    final query = FirebaseFirestore.instance
        .collection('videos')
        .orderBy('timeAdded', descending: true);

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Text(
              'فيديوهات ذات صلة',
              style: TextStyle(
                fontSize: sf(context, 20),
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final allDocs = snapshot.data?.docs ?? [];
              // Filter by same category (by id or by name fallback) and exclude current video
              var related = allDocs
                  .where((d) {
                    final data = d.data();
                    final url = (data['videoUrl'] ?? '').toString();
                    if (url == widget.videoUrl) return false;
                    final cid = (data['categoryId'] ?? '').toString();
                    final cname = (data['category'] ?? '').toString();
                    final byId =
                        _currentCategoryId != null &&
                            _currentCategoryId!.isNotEmpty
                        ? cid == _currentCategoryId
                        : false;
                    final byName =
                        _currentCategoryName != null &&
                            _currentCategoryName!.isNotEmpty
                        ? cname == _currentCategoryName
                        : false;
                    return byId || byName;
                  })
                  .take(10)
                  .toList();

              if (related.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'لا توجد فيديوهات ذات صلة حالياً',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                itemCount: related.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final doc = related[i];
                  final data = doc.data();
                  final title = (data['name'] ?? '').toString();
                  final videoUrl = (data['videoUrl'] ?? '').toString();
                  final description = (data['description'] ?? '').toString();
                  return _relatedVideoTile(
                    title: title,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RunVideosPage(
                            title: title,
                            videoUrl: videoUrl,
                            description: description,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _relatedVideoTile({
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.play_arrow, color: Color(0xFF667EEA)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: sf(context, 16),
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
