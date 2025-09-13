import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/components/shared_video_widgets.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/services/engagement_service.dart';

class RecordedVideosPage extends StatefulWidget {
  const RecordedVideosPage({super.key});

  @override
  State<RecordedVideosPage> createState() => _RecordedVideosPageState();
}

class _RecordedVideosPageState extends State<RecordedVideosPage> {
  String _activeTab = 'all';
  String _sortOption = 'latest'; // latest, oldest, most_viewed, least_viewed
  String?
  _activeCategoryName; // fetched from categories collection for fallback

  String _ytThumb(String url) {
    try {
      final uri = Uri.parse(url);
      String? id;
      if (uri.host.contains('youtu.be')) {
        final seg = uri.pathSegments;
        if (seg.isNotEmpty) id = seg.first;
      } else if (uri.host.contains('youtube.com')) {
        id = uri.queryParameters['v'];
        if (id == null || id.isEmpty) {
          final seg = uri.pathSegments;
          final idx = seg.indexOf('embed');
          if (idx != -1 && idx + 1 < seg.length) id = seg[idx + 1];
        }
      }
      if (id == null || id.isEmpty) return '';
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadActiveCategoryName() async {
    if (_activeTab == 'all') {
      setState(() => _activeCategoryName = null);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .doc(_activeTab)
          .get();
      final name = (snap.data()?['name'] ?? '').toString();
      if (mounted) {
        setState(() => _activeCategoryName = name.isNotEmpty ? name : null);
      }
    } catch (_) {
      if (mounted) setState(() => _activeCategoryName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build base Firestore query with sort only; category filter will be client-side
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'videos',
    );
    switch (_sortOption) {
      case 'oldest':
        query = query.orderBy('timeAdded', descending: false);
        break;
      case 'most_viewed':
        query = query.orderBy('views', descending: true);
        break;
      case 'least_viewed':
        query = query.orderBy('views', descending: false);
        break;
      default: // latest
        query = query.orderBy('timeAdded', descending: true);
    }
    query = query.limit(200);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'تسجيلات البث المباشر',
            style: TextStyle(fontSize: sf(context, 18)),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          elevation: 0.5,
        ),
        backgroundColor: const Color(0xFFF8FAFC),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Continue Watching row
              _buildContinueWatchingRow(),
              const SizedBox(height: 12),
              // Category tabs + sort button (loads from Firestore)
              CategoryTabsWithSort(
                categories: null,
                activeTab: _activeTab,
                onTabSelected: (id) {
                  setState(() => _activeTab = id);
                  _loadActiveCategoryName();
                },
                sortOption: _sortOption,
                onSortSelected: (opt) => setState(() => _sortOption = opt),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      final err = snapshot.error.toString();
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'حدث خطأ أثناء تحميل التسجيلات',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              err,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final allDocs = [...(snapshot.data?.docs ?? [])];
                    // Keep recorded videos by a broad heuristic
                    var docs = allDocs.where((d) {
                      final data = d.data();
                      final rawSrc = (data['source'] ?? '')
                          .toString()
                          .toLowerCase();
                      final src = rawSrc.replaceAll('_', ' ');
                      final liveCh = (data['liveChannel'] ?? '').toString();
                      final isRecFlag =
                          (data['recording'] == true) ||
                          (data['isRecording'] == true);
                      final looksRecorded =
                          src.contains('agora') ||
                          src.contains('recording') ||
                          isRecFlag ||
                          liveCh.isNotEmpty;
                      return looksRecorded;
                    }).toList();

                    // Apply client-side category filter: by categoryId or by category name fallback
                    if (_activeTab != 'all') {
                      docs = docs.where((d) {
                        final data = d.data();
                        final cid = (data['categoryId'] ?? '').toString();
                        final cname = (data['category'] ?? '').toString();
                        final byId = cid == _activeTab;
                        final byName =
                            _activeCategoryName != null &&
                                _activeCategoryName!.isNotEmpty
                            ? cname == _activeCategoryName
                            : false;
                        return byId || byName;
                      }).toList();
                    }
                    if (docs.isEmpty) {
                      // Fallback: show empty state if no recorded videos in this category
                      return const Center(
                        child: Text(
                          'لا توجد تسجيلات في هذا القسم بعد',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      );
                    }

                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final d = docs[index];
                        final data = d.data();
                        final rawName = (data['name'] ?? '').toString();
                        final rawTitle = (data['title'] ?? '').toString();
                        final title =
                            (rawName.isNotEmpty ? rawName : rawTitle).isNotEmpty
                            ? (rawName.isNotEmpty ? rawName : rawTitle)
                            : 'بث مباشر مسجل';
                        final description = (data['description'] ?? '')
                            .toString();
                        final vodUrl = (data['vodUrl'] ?? '').toString();
                        final videoUrl = vodUrl.isNotEmpty
                            ? vodUrl
                            : (data['videoUrl'] ?? '').toString();
                        final views = (data['views'] is int)
                            ? data['views'] as int
                            : int.tryParse('${data['views']}') ?? 0;
                        final thumb = (data['thumbnailUrl'] ?? '').toString();

                        return GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/run_videos',
                              arguments: {
                                'title': title,
                                'videoUrl': videoUrl,
                                'description': description.isEmpty
                                    ? null
                                    : description,
                              },
                            );
                          },
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      thumb.isNotEmpty
                                          ? Image.network(
                                              thumb,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              color: Colors.grey.shade200,
                                              child: Center(
                                                child: Icon(
                                                  Icons.ondemand_video_rounded,
                                                  color: Colors.grey,
                                                  size: sd(context, 48),
                                                ),
                                              ),
                                            ),
                                      Container(color: Colors.black26),
                                      const Center(
                                        child: CircleAvatar(
                                          backgroundColor: Colors.white,
                                          child: Icon(
                                            Icons.play_arrow_rounded,
                                            color: Color(0xFFEA2A33),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: sf(context, 16),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              description.isEmpty
                                                  ? '—'
                                                  : description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.visibility,
                                              size: sd(context, 16),
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              views.toString(),
                                              style: const TextStyle(
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatchingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'أكمل المشاهدة',
          style: TextStyle(
            fontSize: sf(context, 20),
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: EngagementService.instance.myIncompleteProgressStream(
              limit: 15,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'لا يوجد عناصر لم تكتمل مشاهدتها',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final progDoc = docs[i];
                  final metaRef =
                      progDoc.reference.parent.parent; // video_meta/<videoKey>
                  if (metaRef == null) return const SizedBox();
                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: metaRef.get(),
                    builder: (context, metaSnap) {
                      if (!metaSnap.hasData) {
                        return _progressSkeleton();
                      }
                      final meta = metaSnap.data!.data() ?? {};
                      final title = (meta['title'] ?? 'فيديو').toString();
                      final videoUrl = (meta['videoUrl'] ?? '').toString();
                      final description = (meta['description'] ?? '')
                          .toString();
                      final thumb = _ytThumb(videoUrl);
                      final d = progDoc.data();
                      final pos = (d['positionSec'] is int)
                          ? d['positionSec'] as int
                          : int.tryParse('${d['positionSec']}') ?? 0;
                      final dur = (d['durationSec'] is int)
                          ? d['durationSec'] as int
                          : int.tryParse('${d['durationSec']}') ?? 0;
                      final pct = (dur > 0 && pos > 0)
                          ? (pos / dur).clamp(0.0, 1.0)
                          : 0.0;

                      return _progressCard(
                        title: title,
                        thumbnail: thumb,
                        progress: pct,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/run_videos',
                            arguments: {
                              'title': title,
                              'videoUrl': videoUrl,
                              'description': description.isEmpty
                                  ? null
                                  : description,
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _progressCard({
    required String title,
    required String thumbnail,
    required double progress,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbnail.isNotEmpty
                      ? Image.network(thumbnail, fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey.shade200,
                          child: Center(
                            child: Icon(
                              Icons.ondemand_video_rounded,
                              color: Colors.grey,
                              size: sd(context, 48),
                            ),
                          ),
                        ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.4),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF667EEA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: sf(context, 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressSkeleton() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(height: 135, color: Colors.grey.shade200),
          const SizedBox(height: 8),
          Container(
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: Colors.grey.shade200,
          ),
        ],
      ),
    );
  }
}
