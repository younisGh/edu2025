import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:educational_platform/services/engagement_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late DateTimeRange _range;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final end = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: start, end: end);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _rangeLabel(DateTimeRange r) {
    return '${r.start.day}/${r.start.month}/${r.start.year} - ${r.end.day}/${r.end.month}/${r.end.year}';
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );
    if (picked != null) {
      setState(
        () => _range = DateTimeRange(
          start: DateTime(
            picked.start.year,
            picked.start.month,
            picked.start.day,
          ),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 80,
          centerTitle: false,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'لوحة التحليلات',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: sf(context, 22),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'نظرة عامة على الأداء والمشاركة',
                style: TextStyle(
                  fontSize: sf(context, 13),
                  color: const Color(0xFFE5E7EB),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: ArrowScroll(
            scrollController: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.all(sp(context, 24)),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date range filter UI
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.date_range_rounded,
                          color: Color(0xFF667EEA),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _rangeLabel(_range),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                              fontSize: sf(context, 14),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: sd(context, 16),
                              vertical: sd(context, 12),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _pickRange,
                          icon: const Icon(Icons.edit_calendar_rounded),
                          label: const Text('تغيير المدى'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: sp(context, 24)),
                  const _KpiSection(),
                  SizedBox(height: sp(context, 24)),
                  const _TopVideosByViewsSection(),
                  SizedBox(height: sp(context, 24)),
                  _VideosAddedTrendSection(dateRange: _range),
                  SizedBox(height: sp(context, 24)),
                  const _FavoriteVideosSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiSection extends StatelessWidget {
  const _KpiSection();

  Future<int> _countVideos() async {
    final qs = await FirebaseFirestore.instance.collection('videos').get();
    return qs.size;
  }

  Future<int> _sumViews() async {
    final qs = await FirebaseFirestore.instance.collection('video_meta').get();
    int total = 0;
    for (final d in qs.docs) {
      final v = d.data()['views'];
      if (v is int) {
        total += v;
      } else if (v is num) {
        total += v.toInt();
      }
    }
    return total;
  }

  Future<int> _countFavorites() async {
    final qs = await FirebaseFirestore.instance
        .collectionGroup('favorites')
        .get();
    return qs.size;
  }

  String _fmt(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final crossAxisCount = isWide ? 3 : 1;
        return Container(
          padding: EdgeInsets.all(sp(context, 20)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFFAFAFA)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: GridView(
            shrinkWrap: true,
            primary: false,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 3.6 : 3.2,
            ),
            children: [
              _KpiCard(
                title: 'إجمالي المشاهدات',
                icon: Icons.visibility_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                future: _sumViews(),
                formatter: _fmt,
              ),
              _KpiCard(
                title: 'إجمالي الفيديوهات',
                icon: Icons.play_circle_fill_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF34D399)],
                ),
                future: _countVideos(),
                formatter: _fmt,
              ),
              _KpiCard(
                title: 'إجمالي المفضلات',
                icon: Icons.favorite_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                ),
                future: _countFavorites(),
                formatter: _fmt,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Gradient gradient;
  final Future<int> future;
  final String Function(num) formatter;

  const _KpiCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.future,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(sp(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: sd(context, 52),
            height: sd(context, 52),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: sd(context, 26)),
          ),
          SizedBox(width: sp(context, 14)),
          FutureBuilder<int>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 60,
                  child: LinearProgressIndicator(minHeight: 6),
                );
              }
              final value = (snap.data ?? 0).toDouble();
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  formatter(v),
                  style: TextStyle(
                    fontSize: sf(context, 22),
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    letterSpacing: 0.2,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: sp(context, 10)),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: sf(context, 13),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopVideosByViewsSection extends StatelessWidget {
  const _TopVideosByViewsSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.leaderboard_rounded,
                  color: Colors.white,
                  size: sd(context, 24),
                ),
              ),
              SizedBox(width: sp(context, 16)),
              Expanded(
                child: Text(
                  'أعلى 5 فيديوهات حسب المشاهدات',
                  style: TextStyle(
                    fontSize: sf(context, 16),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
          SizedBox(height: sp(context, 16)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('videos')
                .orderBy('views', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('حدث خطأ: ${snapshot.error}'));
              }
              var docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'لا توجد بيانات',
                  style: TextStyle(color: Color(0xFF6B7280)),
                );
              }
              // Fetch real views from video_meta for sorting
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: Future.wait(
                  docs.map((d) async {
                    final data = d.data();
                    final videoUrl = (data['videoUrl'] ?? '').toString();
                    final videoKey = EngagementService.instance.videoKeyFromUrl(
                      videoUrl,
                    );
                    final meta = await FirebaseFirestore.instance
                        .collection('video_meta')
                        .doc(videoKey)
                        .get();
                    final mv = meta.data()?['views'];
                    final realViews = mv is int
                        ? mv
                        : (mv is num ? mv.toInt() : 0);
                    return {
                      'doc': d,
                      'realViews': realViews,
                      'videoKey': videoKey,
                    };
                  }).toList(),
                ),
                builder: (context, metaSnap) {
                  if (metaSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = (metaSnap.data ?? []).toList();
                  items.sort(
                    (a, b) => (b['realViews'] as int).compareTo(
                      a['realViews'] as int,
                    ),
                  );
                  final top5 = items.take(5).toList();
                  if (top5.isEmpty) {
                    return const Text(
                      'لا توجد بيانات',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    );
                  }
                  return Column(
                    children: top5.asMap().entries.map((e) {
                      final rank = e.key + 1;
                      final d =
                          e.value['doc']
                              as QueryDocumentSnapshot<Map<String, dynamic>>;
                      final data = d.data();
                      final title = (data['name'] ?? '').toString();
                      final videoKey = e.value['videoKey'] as String;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8B5CF6,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$rank',
                                style: const TextStyle(
                                  color: Color(0xFF8B5CF6),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title.isEmpty ? 'بدون عنوان' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: sf(context, 16),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.visibility_rounded,
                              color: Color(0xFF8B5CF6),
                            ),
                            const SizedBox(width: 6),
                            StreamBuilder<int>(
                              stream: EngagementService.instance.viewsStream(
                                videoKey,
                              ),
                              builder: (context, snap) {
                                final realViews = snap.data ?? 0;
                                return Text(
                                  realViews.toString(),
                                  style: TextStyle(
                                    color: const Color(0xFF8B5CF6),
                                    fontWeight: FontWeight.bold,
                                    fontSize: sf(context, 14),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VideosAddedTrendSection extends StatelessWidget {
  final DateTimeRange dateRange;
  const _VideosAddedTrendSection({required this.dateRange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF10B981), Color(0xFF34D399)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white,
                  size: sd(context, 24),
                ),
              ),
              SizedBox(width: sp(context, 16)),
              Expanded(
                child: Text(
                  'اتجاه الفيديوهات المضافة',
                  style: TextStyle(
                    fontSize: sf(context, 18),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
          SizedBox(height: sp(context, 16)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('videos')
                .orderBy('timeAdded', descending: true)
                .limit(400)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('حدث خطأ: ${snapshot.error}'));
              }

              final start = DateTime(
                dateRange.start.year,
                dateRange.start.month,
                dateRange.start.day,
              );
              final end = DateTime(
                dateRange.end.year,
                dateRange.end.month,
                dateRange.end.day,
              );

              var docs = snapshot.data?.docs ?? [];

              // Filter by selected range (inclusive)
              docs = docs.where((d) {
                final ts = d.data()['timeAdded'];
                if (ts is! Timestamp) return false;
                final dt = ts.toDate();
                final day = DateTime(dt.year, dt.month, dt.day);
                return !day.isBefore(start) && !day.isAfter(end);
              }).toList();

              // Build day buckets for selected range
              final daysCount = end.difference(start).inDays + 1;
              final List<DateTime> days = List.generate(daysCount, (i) {
                final d = start.add(Duration(days: i));
                return DateTime(d.year, d.month, d.day);
              });

              final Map<DateTime, int> counts = {for (final d in days) d: 0};
              for (final d in docs) {
                final ts = d.data()['timeAdded'];
                if (ts is Timestamp) {
                  final dt = ts.toDate();
                  final key = DateTime(dt.year, dt.month, dt.day);
                  if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
                }
              }

              // Prepare line chart data
              final spots = <FlSpot>[];
              for (int i = 0; i < days.length; i++) {
                final d = days[i];
                final c = (counts[d] ?? 0).toDouble();
                spots.add(FlSpot(i.toDouble(), c));
              }
              final maxY = spots.isEmpty
                  ? 1.0
                  : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

              String dayLabel(DateTime d) => '${d.day}/${d.month}';

              return SizedBox(
                height: 280,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY == 0 ? 1 : maxY + 1,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) =>
                          FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: (days.length / 6).clamp(1, 7).toDouble(),
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= days.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                dayLabel(days[idx]),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        barWidth: 3,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF34D399)],
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF10B981).withValues(alpha: 0.25),
                              const Color(0xFF34D399).withValues(alpha: 0.05),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        dotData: FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FavoriteVideosSection extends StatelessWidget {
  const _FavoriteVideosSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: sp(context, 16)),
              Expanded(
                child: Text(
                  'الفيديوهات المفضلة',
                  style: TextStyle(
                    fontSize: sf(context, 16),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
          SizedBox(height: sp(context, 16)),
          // Aggregate favorites using collectionGroup
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collectionGroup('favorites')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('حدث خطأ: ${snapshot.error}'));
              }
              final favoriteDocs = snapshot.data?.docs ?? [];
              if (favoriteDocs.isEmpty) {
                return const Text(
                  'لا توجد بيانات مفضلة حتى الآن',
                  style: TextStyle(color: Color(0xFF6B7280)),
                );
              }
              // Count favorites per videoKey using parent doc id
              final Map<String, int> counts = {};
              for (final doc in favoriteDocs) {
                final videoMeta =
                    doc.reference.parent.parent; // video_meta/{videoKey}
                final key = videoMeta?.id;
                if (key != null) {
                  counts[key] = (counts[key] ?? 0) + 1;
                }
              }
              // Sort by count desc and take top 5
              final sorted = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final topKeys = sorted.take(5).map((e) => e.key).toList();

              return FutureBuilder<
                List<DocumentSnapshot<Map<String, dynamic>>>
              >(
                future: Future.wait(
                  topKeys.map(
                    (k) => FirebaseFirestore.instance
                        .collection('video_meta')
                        .doc(k)
                        .get(),
                  ),
                ),
                builder: (context, metaSnap) {
                  if (metaSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final metas = metaSnap.data ?? [];
                  return Column(
                    children: metas.map((m) {
                      final data = m.data() ?? {};
                      final title = (data['title'] ?? '').toString();
                      final url = (data['videoUrl'] ?? '').toString();
                      final cnt = counts[m.id] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.play_circle_fill_rounded,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.isEmpty ? url : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.favorite_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$cnt مفضلة',
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
