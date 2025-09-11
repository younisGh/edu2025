import 'dart:async';

import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:educational_platform/components/footer.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:educational_platform/components/video_player_page.dart';
import 'package:educational_platform/services/settings_service.dart';
import 'package:educational_platform/utils/typography.dart';

class GuestDashboard extends StatefulWidget {
  const GuestDashboard({super.key});

  @override
  State<GuestDashboard> createState() => _GuestDashboardState();
}

class _GuestDashboardState extends State<GuestDashboard> {
  String _activeTab = 'all';
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Timer? _scrollTimer;
  final PageStorageKey _pageStorageKey = const PageStorageKey(
    'guestDashboardScroll',
  );
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Do not request focus here, to allow the search field to receive keyboard input
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArrowScroll(
      scrollController: _scrollController,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: false,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFFF8FAFC),
                        Color(0xFFF1F5F9),
                        Color(0xFFE2E8F0),
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                // Main Content with Scroll
                Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  radius: const Radius.circular(8),
                  thickness: 6,
                  child: ListView(
                    key: _pageStorageKey,
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildHeader(),
                      _buildMainContent(),
                      const Footer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF667EEA), // Modern Blue
            Color(0xFF764BA2), // Purple
            Color(0xFF6B46C1), // Deep Purple
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x40667EEA),
            blurRadius: 20,
            offset: Offset(0, 10),
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Top Navigation Bar
              Builder(
                builder: (context) {
                  final width = MediaQuery.of(context).size.width;
                  final isMobile = width < 600;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left placeholder space (hidden on mobile)
                      isMobile
                          ? const SizedBox(width: 0, height: 0)
                          : const SizedBox(width: 48, height: 48),

                      // Login/Signup Buttons (use Wrap on mobile to avoid overflow)
                      Flexible(
                        child: Builder(
                          builder: (context) {
                            final width = MediaQuery.of(context).size.width;
                            final isUltraSmall = width < 360; // special tweak
                            final horizontalPad = isUltraSmall
                                ? 8.0
                                : (isMobile ? 12.0 : 20.0);
                            final verticalPad = isUltraSmall
                                ? 6.0
                                : (isMobile ? 8.0 : 10.0);
                            final minHeight = isUltraSmall
                                ? 30.0
                                : (isMobile ? 36.0 : 44.0);
                            final fontSize = isUltraSmall
                                ? 12.0
                                : (isMobile ? 13.0 : 14.0);
                            final iconSize = isUltraSmall ? 16.0 : 18.0;

                            final buttons = Directionality(
                              textDirection: TextDirection.rtl,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        Navigator.pushNamed(context, '/login'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF6D28D9),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: horizontalPad,
                                        vertical: verticalPad,
                                      ),
                                      minimumSize: Size(0, minHeight),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: Icon(
                                      Icons.login_rounded,
                                      size: iconSize,
                                    ),
                                    label: Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        Navigator.pushNamed(context, '/signup'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: horizontalPad,
                                        vertical: verticalPad,
                                      ),
                                      minimumSize: Size(0, minHeight),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: Icon(
                                      Icons.person_add_alt_1,
                                      size: iconSize,
                                    ),
                                    label: Text(
                                      'إنشاء حساب',
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (isUltraSmall) {
                              // Ensure both buttons stay on one line by scaling if needed
                              return Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: buttons,
                                ),
                              );
                            }

                            // Default behavior (no scaling) on wider screens
                            return Align(
                              alignment: Alignment.centerRight,
                              child: buttons,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (context) {
                  final width = MediaQuery.of(context).size.width;
                  final isMobile = width < 600;
                  return Column(
                    children: [
                      StreamBuilder<AppSettings>(
                        stream: SettingsService.instance.stream(),
                        builder: (context, snap) {
                          final title =
                              (snap.data != null &&
                                  snap.data!.platformTitle.isNotEmpty)
                              ? snap.data!.platformTitle
                              : 'المنصة التعليمية';
                          final desc =
                              (snap.data != null &&
                                  snap.data!.platformDescription.isNotEmpty)
                              ? snap.data!.platformDescription
                              : 'مرحباً بك! ابدأ رحلتك التعليمية الآن.';
                          return Column(
                            children: [
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: sf(context, isMobile ? 24 : 32),
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                desc,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: sf(context, isMobile ? 14 : 16),
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              // Search Bar
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.8),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: TextField(
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: sf(context, 16),
                    color: Color(0xFF1F2937),
                  ),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن الدروس والمحتوى التعليمي...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: sf(context, 14),
                    ),
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(
                        color: Color(0xFF667EEA),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryTabs(),
          const SizedBox(height: 32),
          _buildVideoGrid(),
          const SizedBox(height: 40),
          _buildStatistics(),
          const SizedBox(height: 32),
          _buildRecentVideos(),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('categories')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final cats = <Map<String, String>>[
          {'id': 'all', 'name': 'الكل'},
          ...((snapshot.data?.docs ?? []).map(
            (d) => {'id': d.id, 'name': (d.data()['name'] ?? '').toString()},
          )),
        ];

        final width = MediaQuery.of(context).size.width;
        final isMobile = width < 600;
        final isTiny = width < 345;

        if (isMobile) {
          // Dropdown on mobile
          return Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _activeTab.isEmpty ? 'all' : _activeTab,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isTiny ? 10 : 12,
                      vertical: isTiny ? 8 : 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isTiny ? 10 : 12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isTiny ? 10 : 12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  items: cats.map((c) {
                    final id = c['id'] ?? 'all';
                    final name = c['name'] ?? '';
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: sf(context, isTiny ? 13 : 14),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _activeTab = val);
                  },
                ),
              ),
            ],
          );
        }

        // Horizontal tabs on larger screens
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: cats.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final isActive = _activeTab == category['id'];
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300 + (index * 40)),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = category['id']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: isActive
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              )
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  const Color.fromARGB(255, 156, 191, 248),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isActive
                              ? Colors.transparent
                              : Colors.grey.shade200,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isActive
                                ? const Color(
                                    0xFF667EEA,
                                  ).withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.06),
                            blurRadius: isActive ? 16 : 8,
                            offset: Offset(0, isActive ? 6 : 2),
                          ),
                        ],
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF6B7280),
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: sf(context, 16),
                        ),
                        child: Text(category['name'] ?? ''),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoGrid() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'videos',
    );
    if (_activeTab != 'all') {
      q = q.where('categoryId', isEqualTo: _activeTab);
    }
    // Default ordering by latest
    q = q.orderBy('timeAdded', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        // Client-side search filter
        final filtered = _searchQuery.isEmpty
            ? docs
            : docs.where((d) {
                final data = d.data();
                final name = (data['name'] ?? '').toString().toLowerCase();
                final desc = (data['description'] ?? '')
                    .toString()
                    .toLowerCase();
                final q = _searchQuery.toLowerCase();
                return name.contains(q) || desc.contains(q);
              }).toList();

        if (filtered.isEmpty) {
          return const Center(child: Text('لا توجد فيديوهات متاحة حالياً.'));
        }

        final width = MediaQuery.of(context).size.width;
        final isMobile = width < 600;
        final isTiny = width < 345;
        final crossAxisCount = isMobile
            ? 1
            : width > 1200
            ? 4
            : width > 800
            ? 3
            : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            // Make cards taller on ultra-small screens to avoid vertical overflow
            childAspectRatio: isTiny
                ? 0.85
                : isMobile
                ? 1.05
                : 1.25,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final data = doc.data();
            final title = (data['name'] ?? '').toString();
            final desc = (data['description'] ?? '').toString();
            final videoUrl = (data['videoUrl'] ?? '').toString();
            final thumb = (data['thumbnailUrl'] ?? '').toString();

            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        VideoPlayerPage(title: title, videoUrl: videoUrl),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Colors.grey.shade50],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail / header
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumb.isNotEmpty)
                              Image.network(
                                thumb,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    Container(color: const Color(0xFFEEF2FF)),
                              )
                            else
                              Container(color: const Color(0xFFEEF2FF)),
                            Center(
                              child: Container(
                                width: isTiny ? 40 : (isMobile ? 48 : 64),
                                height: isTiny ? 40 : (isMobile ? 48 : 64),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(
                                    isTiny ? 20 : (isMobile ? 24 : 32),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: isTiny ? 22 : (isMobile ? 26 : 32),
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Meta
                    Container(
                      padding: EdgeInsets.all(isTiny ? 14 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: sf(context, isTiny ? 13 : 14),
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1F2937),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: sf(context, isTiny ? 11 : 12),
                              color: const Color(0xFF6B7280),
                              height: 1.35,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Removed _buildVideoCard (static placeholder). Using Firestore-backed grid instead.

  Widget _buildStatistics() {
    return Container(); // Hide statistics for guests
  }

  Widget _buildRecentVideos() {
    return Container(); // Hide recent videos for guests, as they are part of the main grid
  }
}
