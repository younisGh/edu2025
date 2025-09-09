import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:educational_platform/services/engagement_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class AdminVideoDetailsPage extends StatefulWidget {
  final String title;
  final String videoUrl;
  final String? description;

  const AdminVideoDetailsPage({
    super.key,
    required this.title,
    required this.videoUrl,
    this.description,
  });

  @override
  State<AdminVideoDetailsPage> createState() => _AdminVideoDetailsPageState();
}

class _AdminVideoDetailsPageState extends State<AdminVideoDetailsPage> {
  // Player state
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  YoutubePlayerController? _ytController;
  bool _isYouTube = false;
  bool _isError = false;
  late final String _videoKey;

  // Removed manual PDF link editing; no controller needed.

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
    _initPlayer();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _ytController?.dispose();
    super.dispose();
  }

  Future<void> _uploadPdfAndSetUrl({String? existingUrl}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر قراءة ملف PDF المختار')),
        );
        return;
      }

      final path =
          'pdfs/$_videoKey/${DateTime.now().millisecondsSinceEpoch}.pdf';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final url = await ref.getDownloadURL();

      await EngagementService.instance.setPdfUrl(_videoKey, url);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفع PDF وتحديث الرابط')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل رفع PDF: $e')));
    }
  }

  Future<void> _deleteStoredPdfAndClear(String pdfUrl) async {
    if (pdfUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد ملف PDF مخزّن للحذف')),
      );
      return;
    }
    try {
      final ref = FirebaseStorage.instance.refFromURL(pdfUrl);
      await ref.delete();
    } catch (_) {
      // ignore storage delete errors; still clear the URL
    }
    await EngagementService.instance.clearPdfUrl(_videoKey);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف ملف PDF ومسح الرابط')));
  }

  Future<void> _initPlayer() async {
    try {
      _isYouTube = _detectYouTube(widget.videoUrl);
      if (_isYouTube) {
        final vid = _extractYouTubeId(widget.videoUrl);
        if (vid == null || vid.isEmpty) {
          throw Exception('Invalid YouTube URL');
        }
        _ytController = YoutubePlayerController(
          initialVideoId: vid,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            showLiveFullscreenButton: true,
            forceHD: false,
            enableCaption: true,
          ),
        );
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
        );
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _isError = true);
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
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(title: const Text('تفاصيل الفيديو - لوحة التحكم')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final isWide = maxW >= 1000;
            final colGap = 16.0;
            final itemW = isWide
                ? (maxW - (colGap * 3)) / 2
                : maxW - (colGap * 2);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPlayerCard(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: colGap,
                    runSpacing: colGap,
                    children: [
                      SizedBox(width: itemW, child: _buildInfoCard()),
                      SizedBox(width: itemW, child: _buildPdfCard()),
                      SizedBox(
                        width: itemW,
                        child: _buildCommentsCard(compact: true),
                      ),
                      SizedBox(
                        width: itemW,
                        child: _buildRatingsCard(compact: true),
                      ),
                      SizedBox(
                        width: itemW,
                        child: _buildFavoritesCard(compact: true),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: _isError
                        ? const Text('تعذر تشغيل الفيديو')
                        : _isYouTube
                        ? (_ytController != null)
                              ? YoutubePlayer(controller: _ytController!)
                              : const CircularProgressIndicator()
                        : (_chewieController != null &&
                              _chewieController!
                                  .videoPlayerController
                                  .value
                                  .isInitialized)
                        ? Chewie(controller: _chewieController!)
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title.isEmpty ? 'بدون عنوان' : widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              widget.description ?? 'لا يوجد وصف.',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            const SizedBox(height: 8),
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
                      style: const TextStyle(color: Color(0xFF64748B)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('video_meta')
              .doc(_videoKey)
              .snapshots(),
          builder: (context, snap) {
            final pdfUrl = (snap.data?.data()?['pdfUrl'] ?? '').toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملف PDF',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (pdfUrl.isEmpty) const Text('لا يوجد ملف PDF مرفوع.'),
                if (pdfUrl.isNotEmpty)
                  Row(
                    children: const [
                      Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                      SizedBox(width: 6),
                      Text('ملف PDF مرفوع'),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _uploadPdfAndSetUrl(existingUrl: pdfUrl),
                      icon: const Icon(Icons.upload_file),
                      label: Text(pdfUrl.isEmpty ? 'رفع PDF' : 'استبدال PDF'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: pdfUrl.isEmpty
                          ? null
                          : () => _deleteStoredPdfAndClear(pdfUrl),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'حذف الملف',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: pdfUrl.isEmpty
                          ? null
                          : () async {
                              final uri = Uri.tryParse(pdfUrl);
                              if (uri != null) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('فتح'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Comments card
  Widget _buildCommentsCard({bool compact = false}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'التعليقات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAllCommentsDialog(),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.commentsStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Text('لا توجد تعليقات');
                final show = compact ? docs.take(3).toList() : docs;
                return Column(
                  children: [
                    for (int i = 0; i < show.length; i++) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(show[i].data()['name'] ?? 'مستخدم'),
                        subtitle: Text(show[i].data()['text'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'حذف (إدمن)',
                          onPressed: () async {
                            await EngagementService.instance.adminDeleteComment(
                              _videoKey,
                              show[i].id,
                            );
                          },
                        ),
                      ),
                      if (i != show.length - 1) const Divider(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingsCard({bool compact = false}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'التقييمات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAllRatingsDialog(),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                StreamBuilder<double>(
                  stream: EngagementService.instance.averageRatingStream(
                    _videoKey,
                  ),
                  builder: (context, snap) {
                    final avg = snap.data ?? 0.0;
                    return Text('المتوسط: ${avg.toStringAsFixed(1)}');
                  },
                ),
                const SizedBox(width: 16),
                StreamBuilder<int>(
                  stream: EngagementService.instance.ratingsCountStream(
                    _videoKey,
                  ),
                  builder: (context, snap) {
                    final c = snap.data ?? 0;
                    return Text('العدد: $c');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.ratingsStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Text('لا توجد تقييمات');
                final show = compact ? docs.take(3).toList() : docs;
                return Column(
                  children: [
                    for (int i = 0; i < show.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final d = show[i].data();
                          final uid = (d['userId'] ?? '').toString();
                          final val = (d['value'] is num)
                              ? (d['value'] as num).toInt()
                              : 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(d['name'] ?? uid),
                            subtitle: Text('التقييم: $val/5'),
                          );
                        },
                      ),
                      if (i != show.length - 1) const Divider(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesCard({bool compact = false}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'المفضلة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAllFavoritesDialog(),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.favoritesStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Text('لا يوجد مستخدمون في المفضلة');
                }
                final show = compact ? docs.take(3).toList() : docs;
                return Column(
                  children: [
                    for (int i = 0; i < show.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final d = show[i].data();
                          final uid = (d['userId'] ?? '').toString();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(d['name'] ?? uid),
                            subtitle: const Text(
                              'قام بإضافة الفيديو إلى المفضلة',
                            ),
                          );
                        },
                      ),
                      if (i != show.length - 1) const Divider(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Dialogs for full lists
  void _showAllCommentsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(12),
          title: const Text('كل التعليقات'),
          content: SizedBox(
            width: 600,
            height: 500,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.commentsStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('لا توجد تعليقات'));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final commentId = docs[i].id;
                    return ListTile(
                      title: Text(d['name'] ?? 'مستخدم'),
                      subtitle: Text(d['text'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await EngagementService.instance.adminDeleteComment(
                            _videoKey,
                            commentId,
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showAllRatingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(12),
          title: const Text('كل التقييمات'),
          content: SizedBox(
            width: 600,
            height: 500,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.ratingsStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('لا توجد تقييمات'));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final uid = (d['userId'] ?? '').toString();
                    final val = (d['value'] is num)
                        ? (d['value'] as num).toInt()
                        : 0;
                    return ListTile(
                      title: Text(d['name'] ?? uid),
                      subtitle: Text('التقييم: $val/5'),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showAllFavoritesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(12),
          title: const Text('كل المستخدمين الذين أضافوا إلى المفضلة'),
          content: SizedBox(
            width: 600,
            height: 500,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: EngagementService.instance.favoritesStream(_videoKey),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('لا يوجد مستخدمون في المفضلة'),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final uid = (d['userId'] ?? '').toString();
                    return ListTile(
                      title: Text(d['name'] ?? uid),
                      subtitle: const Text('قام بإضافة الفيديو إلى المفضلة'),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }
}
