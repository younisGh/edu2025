import 'dart:async';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:educational_platform/components/footer.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:educational_platform/homePages/profile_page.dart';
import 'package:educational_platform/homePages/settings_page.dart';
import 'package:educational_platform/homePages/analytics_page.dart';
import 'package:educational_platform/services/engagement_service.dart';
import 'package:educational_platform/components/shared_video_widgets.dart';
import 'package:educational_platform/homePages/live_stream_page.dart';
import 'package:educational_platform/components/admin_send_notification_dialog.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/services/settings_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _activeTab = 'all';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  String _userName = 'المدير'; // Default name
  String? _pictureUrl;
  final PageStorageKey _pageStorageKey = const PageStorageKey(
    'adminDashboardScroll',
  );

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  String _sortOption =
      'latest'; // latest, oldest, most_viewed, least_viewed, favorites_first
  // Pagination (page size and extra pages appended on demand)
  final int _pageSize = 12;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _extraDocs = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    // Listen to search input with debounce
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });
  }

  Future<void> _fetchUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (mounted && userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _userName =
                userData['name'] ??
                (user.displayName != null
                    ? '${user.displayName} المدير'
                    : 'المدير');
            _pictureUrl = userData['pictureUrl'];
          });
        }
      } catch (e) {
        debugPrint('Error fetching admin data: $e');
        if (mounted) {
          setState(() {
            _userName = user.displayName ?? 'المدير';
          });
        }
      }
    }
  }

  void _navigateToProfile() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const ProfilePage()));
      }
    });
  }

  void _navigateToManageVideos() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).pushNamed('/manage_videos');
      }
    });
  }

  void _navigateToSettings() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
      }
    });
  }

  void _navigateToAnalytics() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AnalyticsPage()));
      }
    });
  }

  void _navigateToLiveStream() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const LiveStreamPage()));
      }
    });
  }

  void _navigateToUsers() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).pushNamed('/users_page');
      }
    });
  }

  void _navigateToViewingRequests() {
    Navigator.of(context).pop(); // Close the drawer first
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).pushNamed('/viewing_requests');
      }
    });
  }

  void _toggleSidebar() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _openSendNotificationDialog() async {
    // Close drawer if open
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const AdminSendNotificationDialog(),
    );
    if (!mounted) return;
    if (result == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال الإشعار بنجاح')));
    }
  }

  // Debounced search handler
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value;
        // Reset pagination when search changes
        _extraDocs = [];
        _hasMore = true;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArrowScroll(
      scrollController: _scrollController,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFF8FAFC),
          drawer: _buildSidebar(),
          body: SafeArea(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SingleChildScrollView(
                key: _pageStorageKey,
                controller: _scrollController,
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildMainContent(),
                    const Footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive drawer width: narrower on very small screens, fixed on medium, slightly wider on large
    double drawerWidth;
    if (screenWidth < 360) {
      drawerWidth = screenWidth * 0.85; // very small phones
    } else if (screenWidth < 600) {
      drawerWidth = screenWidth * 0.72; // small phones
    } else if (screenWidth < 900) {
      drawerWidth = 320; // tablets / small desktops
    } else {
      drawerWidth = 360; // large desktops
    }
    // Clamp to sensible bounds
    drawerWidth = drawerWidth.clamp(240.0, 420.0);

    return Drawer(
      width: drawerWidth,
      child: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color.fromARGB(255, 207, 235, 247),
              Color(0xFFF5F5F5),
            ],
          ),
        ),
        child: Column(
          children: [
            _buildSidebarHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildSidebarItem(Icons.home, 'الرئيسية', true),
                      _buildSidebarItem(
                        Icons.movie,
                        'الفيديوهات',
                        false,
                        onTap: _navigateToManageVideos,
                      ),

                      _buildSidebarItem(
                        Icons.live_tv,
                        'البث المباشر',
                        false,
                        onTap: _navigateToLiveStream,
                      ),

                      _buildSidebarItem(
                        Icons.group,
                        'إدارة المستخدمين',
                        false,
                        onTap: _navigateToUsers,
                      ),
                      _buildSidebarItem(
                        Icons.visibility,
                        'طلبات المشاهدة',
                        false,
                        onTap: _navigateToViewingRequests,
                      ),
                      _buildSidebarItem(
                        Icons.notifications_active,
                        'إرسال إشعار',
                        false,
                        onTap: _openSendNotificationDialog,
                      ),
                      _buildSidebarItem(
                        Icons.bar_chart,
                        'التحليلات',
                        false,
                        onTap: _navigateToAnalytics,
                      ),
                      _buildSidebarItem(
                        Icons.settings,
                        'الإعدادات',
                        false,
                        onTap: _navigateToSettings,
                      ),
                      const SizedBox(height: 16),
                      _buildSidebarItem(
                        Icons.person,
                        'الملف الشخصي',
                        false,
                        onTap: _navigateToProfile,
                      ),
                      _buildSidebarItem(
                        Icons.logout,
                        'تسجيل الخروج',
                        false,
                        isLogout: true,
                      ),
                      const SizedBox(height: 24), // Bottom padding
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'لوحة التحكم',
            style: TextStyle(
              fontSize: sf(context, 24),
              fontWeight: FontWeight.bold,
              color: const Color(0xFF6D28D9),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: Colors.grey, size: sd(context, 20)),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String title,
    bool isActive, {
    bool isLogout = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: (isLogout || onTap != null)
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(8),
          onTap: isLogout ? _logout : onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFEDE9FE) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isLogout
                      ? Colors.red
                      : isActive
                      ? const Color(0xFF6D28D9)
                      : Colors.grey,
                  size: sd(context, 20),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: isLogout
                        ? Colors.red
                        : isActive
                        ? const Color(0xFF6D28D9)
                        : const Color(0xFF374151),
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    fontSize: sf(context, 14),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Menu Button
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.3),
                          Colors.white.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _toggleSidebar,
                      icon: const Icon(
                        Icons.menu_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),

                  // User Profile Section (responsive)
                  Flexible(
                    child: Builder(
                      builder: (context) {
                        final width = MediaQuery.of(context).size.width;
                        final isMobile = width < 600;
                        final isTiny = width < 360;
                        final avatarOuter = isMobile ? 24.0 : 28.0;
                        final avatarInner = isMobile ? 22.0 : 26.0;
                        final displayName = isTiny
                            ? (_userName.split(' ').isNotEmpty
                                  ? _userName.split(' ').first
                                  : _userName)
                            : _userName;
                        return Directionality(
                          textDirection: TextDirection.rtl,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Tooltip(
                                message: 'إرسال إشعار',
                                child: IconButton(
                                  onPressed: _openSendNotificationDialog,
                                  icon: const Icon(
                                    Icons.notifications_active,
                                    color: Colors.white,
                                  ),
                                  iconSize: isMobile ? 20 : 24,
                                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: sf(
                                    context,
                                    isTiny ? 12 : (isMobile ? 14 : 18),
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              CircleAvatar(
                                radius: avatarOuter,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                                child: CircleAvatar(
                                  radius: avatarInner,
                                  backgroundImage:
                                      _pictureUrl != null &&
                                          _pictureUrl!.isNotEmpty
                                      ? NetworkImage(_pictureUrl!)
                                      : null,
                                  backgroundColor: const Color(0xFF667EEA),
                                  child:
                                      _pictureUrl == null ||
                                          _pictureUrl!.isEmpty
                                      ? Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: isMobile ? 22 : 28,
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Menu Button
                ],
              ),
              Builder(
                builder: (context) {
                  final width = MediaQuery.of(context).size.width;
                  final isMobile = width < 600;
                  final isTiny = width < 360;
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
                              : 'مرحباً بك مجدداً، أداء رائع اليوم!';
                          return Column(
                            children: [
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: sf(
                                    context,
                                    isTiny ? 18 : (isMobile ? 24 : 32),
                                  ),
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                desc,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: sf(
                                    context,
                                    isTiny ? 12 : (isMobile ? 14 : 16),
                                  ),
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
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن دروس أو محتوى',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: sf(context, 16),
                    ),
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
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
          const SizedBox(height: 24),
          _buildFirestoreVideoGrid(),
          const SizedBox(height: 40),
          _buildStatistics(),
          const SizedBox(height: 32),
          _buildRecentVideos(),
        ],
      ),
    );
  }

  // Category tabs + sort using shared widget
  Widget _buildCategoryTabs() {
    return CategoryTabsWithSort(
      activeTab: _activeTab,
      onTabSelected: (id) => setState(() {
        _activeTab = id;
        _extraDocs = [];
        _hasMore = true; // reset pagination
      }),
      sortOption: _sortOption,
      onSortSelected: (opt) => setState(() {
        _sortOption = opt;
        _extraDocs = [];
        _hasMore = true; // reset pagination
      }),
    );
  }

  Query<Map<String, dynamic>> _buildBaseQuery() {
    final collection = FirebaseFirestore.instance.collection('videos');
    switch (_sortOption) {
      case 'oldest':
        return collection
            .orderBy('timeAdded', descending: false)
            .limit(_pageSize);
      case 'most_viewed':
        return collection.orderBy('views', descending: true).limit(_pageSize);
      case 'least_viewed':
        return collection.orderBy('views', descending: false).limit(_pageSize);
      case 'favorites_first':
        // Base sort by latest, then we'll reorder favorites client-side
        return collection
            .orderBy('timeAdded', descending: true)
            .limit(_pageSize);
      case 'latest':
      default:
        return collection
            .orderBy('timeAdded', descending: true)
            .limit(_pageSize);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final baseQuery = _buildBaseQuery().limit(_pageSize);
      // Determine the last document of the currently displayed combined list
      // We'll derive it from the latest known extraDocs if any, else from the first page snapshot (passed indirectly)
      // To get a stable cursor, we need the last document in the combined list; we'll fetch the first page again and append extras to determine the cursor.
      final firstPageSnap = await _buildBaseQuery().get();
      var combined = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      combined.addAll(firstPageSnap.docs);
      combined.addAll(_extraDocs);
      if (combined.isEmpty) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
        return;
      }
      final lastDoc = combined.last;
      final nextSnap = await baseQuery.startAfterDocument(lastDoc).get();
      if (nextSnap.docs.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }
      setState(() {
        _extraDocs.addAll(nextSnap.docs);
        if (nextSnap.docs.length < _pageSize) _hasMore = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تحميل المزيد: $e')));
      }
    }
  }

  // Firestore video grid using shared ResponsiveVideoGrid
  Widget _buildFirestoreVideoGrid() {
    final baseQuery = _buildBaseQuery();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: baseQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'حدث خطأ أثناء جلب الفيديوهات',
              style: TextStyle(color: Colors.red.shade700),
            ),
          );
        }
        var docs = snapshot.data?.docs ?? [];
        // Combine with extra pages
        var combined = <QueryDocumentSnapshot<Map<String, dynamic>>>[
          ...docs,
          ..._extraDocs,
        ];

        // Client-side filter by active tab (category) if present
        if (_activeTab != 'all') {
          combined = combined.where((d) {
            final data = d.data();
            final catId = (data['categoryId'] ?? '').toString();
            final cat = (data['category'] ?? '').toString();
            return catId == _activeTab || cat == _activeTab;
          }).toList();
        }

        // Client-side filter by search query (name, description, category)
        final q = _searchQuery.trim().toLowerCase();
        if (q.isNotEmpty) {
          combined = combined.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final desc = (data['description'] ?? '').toString().toLowerCase();
            final cat = (data['category'] ?? '').toString().toLowerCase();
            return name.contains(q) || desc.contains(q) || cat.contains(q);
          }).toList();
        }

        if (combined.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد فيديوهات متاحة حالياً',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        // If sorting by favorites first, reorder client-side using EngagementService
        if (_sortOption == 'favorites_first') {
          return FutureBuilder<
            List<QueryDocumentSnapshot<Map<String, dynamic>>>
          >(
            future: _orderFavoritesFirst(combined),
            builder: (context, favSnap) {
              final ordered = favSnap.data ?? combined;
              return ResponsiveVideoGrid(
                itemCount: ordered.length,
                childAspectRatio: 1.2,
                itemBuilder: (context, index) {
                  return _buildFirestoreVideoCard(ordered[index]);
                },
              );
            },
          );
        }

        // Default grid with Load More button
        return Column(
          children: [
            ResponsiveVideoGrid(
              itemCount: combined.length,
              childAspectRatio: 1.2,
              itemBuilder: (context, index) {
                return _buildFirestoreVideoCard(combined[index]);
              },
            ),
            const SizedBox(height: 16),
            if (_hasMore)
              FilledButton.icon(
                onPressed: _isLoadingMore ? null : _loadMore,
                icon: _isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(
                  _isLoadingMore ? '...جاري التحميل' : 'تحميل المزيد',
                ),
              ),
          ],
        );
      },
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _orderFavoritesFirst(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final service = EngagementService.instance;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> favs = [];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> nonFavs = [];

    for (final d in docs) {
      final data = d.data();
      final url = (data['videoUrl'] ?? '').toString();
      if (url.isEmpty) {
        nonFavs.add(d);
      } else {
        final key = service.videoKeyFromUrl(url);
        final isFav = await service.isFavorite(key);
        if (isFav) {
          favs.add(d);
        } else {
          nonFavs.add(d);
        }
      }
    }
    return [...favs, ...nonFavs];
  }

  Widget _buildFirestoreVideoCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = (data['name'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final videoUrl = ((data['videoUrl'] ?? data['vodUrl']) ?? '').toString();
    final videoType = (data['videoType'] ?? 'free').toString();
    final thumbFromDoc = (data['thumbnailUrl'] ?? '').toString();

    final thumb = thumbFromDoc.isNotEmpty
        ? thumbFromDoc
        : _deriveYoutubeThumbnail(videoUrl);

    // Date (timeAdded)
    String dateStr = '';
    final ts = data['timeAdded'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    final service = EngagementService.instance;
    final videoKey = service.videoKeyFromUrl(videoUrl);

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/run_videos',
          arguments: {
            'title': title,
            'videoUrl': videoUrl,
            'description': description,
          },
        );
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb.isNotEmpty)
                    Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: const Color(0xFFE5E7EB),
                        child: const Center(
                          child: Icon(
                            Icons.ondemand_video_rounded,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFFE5E7EB),
                      child: const Center(
                        child: Icon(
                          Icons.ondemand_video_rounded,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  // Dark overlay to improve foreground contrast
                  Container(color: Colors.black26),
                  // Play button overlay
                  const Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),

                  // Top-right: Video type badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            videoType == 'paid'
                                ? Colors.amber.shade700
                                : Colors.green.shade600,
                            videoType == 'paid'
                                ? Colors.amber.shade600
                                : Colors.green.shade500,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        videoType == 'paid' ? 'مدفوع' : 'مجاني',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                  // Bottom-left: views badge (live from EngagementService)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.remove_red_eye_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          StreamBuilder<int>(
                            stream: service.viewsStream(videoKey),
                            builder: (context, snap) {
                              final v = snap.data ?? 0;
                              return Text(
                                '$v',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom-right: date badge
                  if (dateStr.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        title.isEmpty ? 'بدون عنوان' : title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        description.isEmpty ? 'لا يوجد وصف' : description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper: derive YouTube thumbnail URL from videoUrl
  String _deriveYoutubeThumbnail(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      String? id;
      if (uri.host.contains('youtu.be')) {
        id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      } else if (uri.host.contains('youtube.com')) {
        if (uri.path.contains('/watch')) {
          id = uri.queryParameters['v'];
        } else if (uri.path.contains('/embed/')) {
          final parts = uri.pathSegments;
          final idx = parts.indexOf('embed');
          if (idx != -1 && idx + 1 < parts.length) id = parts[idx + 1];
        }
      }
      if (id == null || id.isEmpty) return '';
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    } catch (_) {
      return '';
    }
  }

  Widget _buildStatistics() {
    final width = MediaQuery.of(context).size.width;
    final isTiny = width < 360;
    return Container(
      padding: EdgeInsets.all(isTiny ? 16 : 32),
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
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إحصائيات المنصة',
            style: TextStyle(
              fontSize: isTiny ? 16 : 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          SizedBox(height: isTiny ? 12 : 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Responsive columns: 1 on very small, 2 on tablets, 3 on desktop, 4 on wide desktop
              int cols = 3;
              if (w < 520) {
                cols = 1;
              } else if (w < 900) {
                cols = 2;
              } else if (w > 1400) {
                cols = 4;
              }
              final aspect = w < 520 ? 2.0 : (w < 900 ? 2.2 : 2.4);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: isTiny ? 10 : 16,
                mainAxisSpacing: isTiny ? 10 : 16,
                childAspectRatio: aspect,
                children: [
                  // Users count
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildStatCard(
                        'المستخدمون',
                        count.toString(),
                        '',
                        Icons.group,
                        const Color.fromARGB(255, 101, 99, 244),
                        const Color.fromARGB(0, 255, 255, 255),
                      );
                    },
                  ),
                  // Videos count
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('videos')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildStatCard(
                        'الفيديوهات',
                        count.toString(),
                        '',
                        Icons.videocam_rounded,
                        const Color(0xFFEC4899),
                        const Color(0xFFFDF2F8),
                      );
                    },
                  ),
                  // Total views from video_meta
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('video_meta')
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      int totalViews = 0;
                      for (final d in docs) {
                        final v = d.data()['views'];
                        if (v is int) {
                          totalViews += v;
                        } else if (v is num) {
                          totalViews += v.toInt();
                        }
                      }
                      return _buildStatCard(
                        'المشاهدات',
                        totalViews.toString(),
                        '',
                        Icons.visibility_rounded,
                        const Color(0xFF10B981),
                        const Color(0xFFECFDF5),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color iconColor,
    Color bgColor,
  ) {
    final width = MediaQuery.of(context).size.width;
    final isTiny = width < 360;
    return Container(
      padding: EdgeInsets.all(isTiny ? 14 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgColor, bgColor.withValues(alpha: .8)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: .1), width: 1),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: .15),
            blurRadius: isTiny ? 12 : 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: isTiny ? 6 : 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isTiny ? 10 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [iconColor, iconColor.withValues(alpha: .8)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: .3),
                  blurRadius: isTiny ? 8 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: isTiny ? 20 : 26),
          ),
          SizedBox(width: isTiny ? 8 : 14),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(
              begin: 0,
              end: double.tryParse(value.replaceAll(',', '')) ?? 0,
            ),
            builder: (context, v, _) {
              return Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: isTiny ? 20 : 28,
                  fontWeight: FontWeight.w800,
                  color: iconColor,
                ),
              );
            },
          ),
          SizedBox(width: isTiny ? 6 : 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentVideos() {
    final width = MediaQuery.of(context).size.width;
    final isTiny = width < 360;
    const palette = [
      Color(0xFF667EEA),
      Color(0xFFEC4899),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
    ];

    // No local header() widget; section title is built inline below.

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('videos')
          .orderBy('timeAdded', descending: true)
          // Fetch more to allow multiple categories in the latest window
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SizedBox(height: 4),
              LinearProgressIndicator(minHeight: 3),
              SizedBox(height: 16),
            ],
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'تعذر جلب أحدث الفيديوهات',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
          );
        }

        var docs = snapshot.data?.docs ?? [];

        // Filter by active category tab (matches logic in _buildFirestoreVideoGrid)
        if (_activeTab != 'all') {
          docs = docs.where((d) {
            final data = d.data();
            final catId = (data['categoryId'] ?? '').toString();
            final cat = (data['category'] ?? '').toString();
            return catId == _activeTab || cat == _activeTab;
          }).toList();
        }

        // Filter by search query
        final q = _searchQuery.trim().toLowerCase();
        if (q.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final desc = (data['description'] ?? '').toString().toLowerCase();
            final cat = (data['category'] ?? '').toString().toLowerCase();
            return name.contains(q) || desc.contains(q) || cat.contains(q);
          }).toList();
        }

        if (docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SizedBox(height: 8),
              Text(
                'لا توجد فيديوهات حديثة متاحة الآن',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ],
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('categories')
              .snapshots(),
          builder: (context, catSnap) {
            final Map<String, String> catMap = {'': 'غير مصنف'};
            for (final d in (catSnap.data?.docs ?? [])) {
              catMap[d.id] = (d.data()['name'] ?? '').toString();
            }
            final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
            grouped = {};
            for (final d in docs) {
              final data = d.data();
              final catId = (data['categoryId'] ?? '').toString();
              final catNameFromId = catMap[catId] ?? '';
              final fallbackName = (data['category'] ?? '').toString();
              final catName = (catNameFromId.isNotEmpty)
                  ? catNameFromId
                  : (fallbackName.isNotEmpty ? fallbackName : 'غير مصنف');
              grouped.putIfAbsent(catName, () => []);
              grouped[catName]!.add(d);
            }
            final groupEntries = grouped.entries.toList()
              ..sort((a, b) {
                final ta = a.value.first.data()['timeAdded'];
                final tb = b.value.first.data()['timeAdded'];
                if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                return 0;
              });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.video_library_rounded,
                      color: Color(0xFF667EEA),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'أحدث الفيديوهات',
                      style: TextStyle(
                        fontSize: isTiny ? 18 : 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTiny ? 12 : 24),
                ...groupEntries.map((group) {
                  final items = group.value.take(10).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final d = entry.value;
                          final data = d.data();
                          final title = (data['name'] ?? '').toString();
                          final description = (data['description'] ?? '')
                              .toString();
                          final views = (data['views'] is int)
                              ? data['views'] as int
                              : int.tryParse('${data['views']}') ?? 0;
                          final videoUrl = (data['videoUrl'] ?? '').toString();
                          final thumbFromDoc = (data['thumbnailUrl'] ?? '')
                              .toString();
                          final thumb = thumbFromDoc.isNotEmpty
                              ? thumbFromDoc
                              : _deriveYoutubeThumbnail(videoUrl);
                          final duration = (data['duration'] ?? '--:--')
                              .toString();
                          final ts = data['timeAdded'];
                          String dateStr = '';
                          if (ts is Timestamp) {
                            final dt = ts.toDate();
                            dateStr =
                                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                          }
                          final color = palette[index % palette.length];

                          if (isTiny) {
                            final videoKey = EngagementService.instance
                                .videoKeyFromUrl(videoUrl);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thumbnail first
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: thumb.isNotEmpty
                                          ? Image.network(
                                              thumb,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stack,
                                                  ) => Container(
                                                    color: const Color(
                                                      0xFFE5E7EB,
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons
                                                            .ondemand_video_rounded,
                                                        size: 28,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: const Color(0xFFE5E7EB),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.ondemand_video_rounded,
                                                  size: 28,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Title + views only
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title.isEmpty ? 'بدون عنوان' : title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.visibility_rounded,
                                        size: 14,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                      const SizedBox(width: 4),
                                      StreamBuilder<int>(
                                        stream: EngagementService.instance
                                            .viewsStream(videoKey),
                                        builder: (context, snap) {
                                          final live = snap.data ?? views;
                                          final c = live > 0
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF6B7280);
                                          return Text(
                                            live.toString(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }

                          return GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                '/run_videos',
                                arguments: {
                                  'title': title.isEmpty ? 'بدون عنوان' : title,
                                  'videoUrl': videoUrl,
                                  'description': description.isNotEmpty
                                      ? description
                                      : null,
                                },
                              );
                            },
                            child: AnimatedContainer(
                              duration: Duration(
                                milliseconds: 300 + (index * 80),
                              ),
                              curve: Curves.easeOutBack,
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Colors.grey.shade50],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                    spreadRadius: 0,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 140,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          color.withValues(alpha: 0.8),
                                          color,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (thumb.isNotEmpty)
                                            Image.network(
                                              thumb,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stack,
                                                  ) => Container(
                                                    color: const Color(
                                                      0xFFE5E7EB,
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons
                                                            .ondemand_video_rounded,
                                                        size: 36,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          else
                                            Container(
                                              color: const Color(0xFFE5E7EB),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.ondemand_video_rounded,
                                                  size: 36,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          Container(
                                            color: Colors.black.withValues(
                                              alpha: 0.26,
                                            ),
                                          ),
                                          Center(
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: color,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          if (!isTiny)
                                            Positioned(
                                              bottom: 8,
                                              right: 8,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  duration,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title.isEmpty ? 'بدون عنوان' : title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1F2937),
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                (group.key.isEmpty
                                                    ? 'غير مصنف'
                                                    : group.key),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.visibility_rounded,
                                                  size: 14,
                                                  color: Colors.grey.shade500,
                                                ),
                                                const SizedBox(width: 4),
                                                StreamBuilder<int>(
                                                  stream: EngagementService
                                                      .instance
                                                      .viewsStream(
                                                        EngagementService
                                                            .instance
                                                            .videoKeyFromUrl(
                                                              videoUrl,
                                                            ),
                                                      ),
                                                  builder: (context, snap) {
                                                    final live =
                                                        snap.data ?? views;
                                                    final c = live > 0
                                                        ? const Color(
                                                            0xFF10B981,
                                                          )
                                                        : Colors.grey.shade500;
                                                    return Text(
                                                      live.toString(),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: c,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (!isTiny)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          dateStr.isEmpty ? '' : dateStr,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF10B981),
                                                Color(0xFF059669),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF10B981,
                                                ).withValues(alpha: 0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'جديد',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  void _logout() async {
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/guest_dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error logging out: $e');
    }
  }
}
