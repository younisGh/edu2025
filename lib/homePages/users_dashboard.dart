import 'dart:async';
import 'dart:ui';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:educational_platform/components/footer.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/services/settings_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:educational_platform/run_videos.dart';
import 'package:educational_platform/services/engagement_service.dart';
import 'package:educational_platform/components/shared_video_widgets.dart';
import 'package:educational_platform/liveStreamPage.dart'; // Added import
import 'package:educational_platform/components/notification_bell.dart';

class UsersDashboard extends StatefulWidget {
  const UsersDashboard({super.key});

  @override
  State<UsersDashboard> createState() => _UsersDashboardState();
}

//

class _UsersDashboardState extends State<UsersDashboard>
    with TickerProviderStateMixin {
  String _activeTab = 'all';
  bool _sidebarOpen = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late AnimationController _sidebarController;
  late Animation<Offset> _sidebarSlideAnimation;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Timer? _scrollTimer;
  String _userName = 'المستخدم'; // Default name
  String? _photoUrl;
  final PageStorageKey _pageStorageKey = const PageStorageKey(
    'userDashboardScroll',
  );
  String _sortOption =
      'latest'; // latest, oldest, most_viewed, least_viewed

  // Search state
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';

  // Active category name for fallback filtering (for legacy videos with only category name)
  String? _activeCategoryName;

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

  

  // Firestore helpers and card UI (moved inside State)
  Widget _buildFirestoreVideoCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = (data['name'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    // Truncate for grid display: title -> 6 words, description -> 10 words
    final truncatedTitle = (() {
      final words = title.trim().split(RegExp(r'\s+'));
      if (words.length <= 6) return title;
      return '${words.sublist(0, 6).join(' ')}…';
    })();
    final truncatedDesc = (() {
      final words = description.trim().split(RegExp(r'\s+'));
      if (words.length <= 10) return description;
      return '${words.sublist(0, 10).join(' ')}…';
    })();
    final videoUrl = ((data['videoUrl'] ?? data['vodUrl']) ?? '').toString();
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RunVideosPage(title: title, videoUrl: videoUrl),
          ),
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
            // Thumbnail
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
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
                  // Dark overlay to improve foreground contrast (matches admin)
                  Container(color: Colors.black26),
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
                          children: const [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            // Text below set outside const due to dynamic dateStr; replaced below
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: FutureBuilder<bool>(
                      future: service.isFavorite(videoKey),
                      builder: (context, snap) {
                        final isFav = snap.data == true;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await service.toggleFavorite(videoKey);
                              if (mounted) setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: isFav
                                    ? const Color(0xFFEC4899)
                                    : Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Play button overlay (responsive)
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final w = MediaQuery.of(context).size.width;
                        final isMobile = w < 600;
                        final isTiny = w < 345;
                        final pad = isTiny ? 8.0 : (isMobile ? 10.0 : 12.0);
                        final iconSize = isTiny
                            ? 24.0
                            : (isMobile ? 30.0 : 36.0);
                        return Center(
                          child: Container(
                            padding: EdgeInsets.all(pad),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: const Color(0xFFEA2A33),
                              size: iconSize,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Inject date text next to the calendar icon (non-const)
                  if (dateStr.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 28,
                          ), // occupy icon+spacing width
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
                ],
              ),
            ),
            // Texts wrapped in Flexible to avoid overflow in constrained heights
            Flexible(
              fit: FlexFit.loose,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Text(
                      truncatedTitle.isEmpty ? 'بدون عنوان' : truncatedTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      truncatedDesc.isEmpty ? 'لا يوجد وصف' : truncatedDesc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
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

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    // Do not steal focus at screen load; allow TextFields (like search) to receive input
    _sidebarController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _sidebarSlideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _sidebarController, curve: Curves.easeInOut),
        );

    // Debounced search listener
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });

    // Initialize active category name (will be null for 'all')
    _loadActiveCategoryName();
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
          String? pic = userData['pictureUrl'];
          String? resolved;
          if (pic != null && pic.isNotEmpty) {
            resolved = await _resolvePhotoUrl(pic);
          }
          if (!mounted) return;
          setState(() {
            _userName = userData['name'] ?? user.displayName ?? 'المستخدم';
            _photoUrl = resolved ?? pic;
          });
        } else {
          // Fallback if user document doesn't exist
          setState(() {
            _userName = user.displayName ?? 'المستخدم';
            _photoUrl = null;
          });
        }
      } catch (e) {
        debugPrint('Error fetching user data: $e');
        if (mounted) {
          setState(() {
            // Fallback to display name from auth if Firestore fails
            _userName = user.displayName ?? 'المستخدم';
            _photoUrl = null;
          });
        }
      }
    }
  }

  Future<String?> _resolvePhotoUrl(String pictureUrl) async {
    try {
      if (pictureUrl.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(pictureUrl);
        return await ref.getDownloadURL();
      }
      return pictureUrl;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sidebarController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarOpen = !_sidebarOpen;
    });
    if (_sidebarOpen) {
      _sidebarController.forward();
    } else {
      _sidebarController.reverse();
    }
  }

  Future<void> _logout() async {
    bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تأكيد تسجيل الخروج'),
          content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      try {
        await _auth.signOut();
        if (mounted) {
          _toggleSidebar(); // Close sidebar if open
          Navigator.pushReplacementNamed(context, '/guest_dashboard');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ في تسجيل الخروج: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
                // Sidebar Overlay
                if (_sidebarOpen)
                  GestureDetector(
                    onTap: _toggleSidebar,
                    child: Container(
                      color: Colors.black.withAlpha(35),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                // Animated Sidebar
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _sidebarSlideAnimation,
                    child: _buildSidebar(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    // Determine which item is active, can be enhanced later if needed
    // For now, only 'الرئيسية' can be active or none if on another page like LiveStream
    // This logic might need to be passed down or managed by a state manager for complex navigation
    final currentRoute = ModalRoute.of(context)?.settings.name;
    bool isHomePageActive =
        currentRoute == null ||
        currentRoute == '/users_dashboard'; // Adjust as per your named routes

    return Container(
      width: 320,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color.fromARGB(255, 207, 235, 247),
            Color(0xFFF5F5F5),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 32,
            offset: const Offset(8, 0),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(2, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'القائمة',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6D28D9),
                  ),
                ),
                IconButton(
                  onPressed: _toggleSidebar,
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildSidebarItem(
                    Icons.home,
                    'الرئيسية',
                    isHomePageActive, // Use dynamic active state
                    onTap: () {
                      _toggleSidebar();
                      // Optional: Navigate to home if not already there,
                      // or simply close sidebar if already on home.
                      // For simplicity, just closing.
                    },
                  ),
                  // Join Live item: disabled when no live is active
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('live_channels')
                        .doc('edu')
                        .snapshots(),
                    builder: (context, snap) {
                      // snap.data is AsyncSnapshot's data (DocumentSnapshot) and can be null
                      final st = (snap.data?.data()?['status'] ?? '')
                          .toString();
                      final isLive = st == 'live';
                      return _buildSidebarItem(
                        Icons.sensors,
                        'الانظمام للبث المباشر',
                        false,
                        onTap: isLive
                            ? () async {
                                // Double-check latest status before navigation
                                try {
                                  final doc = await FirebaseFirestore.instance
                                      .collection('live_channels')
                                      .doc('edu')
                                      .get();
                                  final latest = (doc.data()?['status'] ?? '')
                                      .toString();
                                  if (latest == 'live') {
                                    _toggleSidebar();
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LiveStreamPage(),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'لا يوجد بث مباشر حالياً',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تعذر التحقق من حالة البث'),
                                    ),
                                  );
                                }
                              }
                            : null,
                      );
                    },
                  ),
                  _buildSidebarItem(
                    Icons.notifications,
                    'الإشعارات',
                    false,
                    onTap: () {
                      _toggleSidebar();
                      Navigator.pushNamed(context, '/notifications');
                    },
                  ),
                  const Spacer(), // This will push the following items to the bottom
                  _buildSidebarItem(
                    Icons.person,
                    'الملف الشخصي',
                    false, // Make this dynamic if you have a profile page
                    onTap: () {
                      _toggleSidebar();
                      Navigator.pushNamed(context, '/profile_page');
                    },
                  ),
                  _buildSidebarItem(
                    Icons.logout,
                    'تسجيل الخروج',
                    false,
                    onTap: _logout, // Directly use the _logout method
                  ),
                  const SizedBox(height: 24), // Bottom padding
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String title,
    bool isActive, {
    VoidCallback? onTap, // Changed parameter: general onTap
    // bool isLogout = false, // Removed isLogout, handled by onTap directly
  }) {
    // Determine color based on title for logout, or isActive for others
    Color iconColor = Colors.grey;
    Color textColor = const Color(0xFF374151);
    FontWeight fontWeight = FontWeight.w500;

    if (title == 'تسجيل الخروج') {
      iconColor = Colors.red;
      textColor = Colors.red;
    } else if (isActive) {
      iconColor = const Color(0xFF6D28D9);
      textColor = const Color(0xFF6D28D9);
      fontWeight = FontWeight.bold;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap ?? () {}, // Use provided onTap or do nothing
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive && title != 'تسجيل الخروج'
                  ? const Color(0xFFEDE9FE)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(color: textColor, fontWeight: fontWeight),
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

                  // User Profile Section
                  Row(
                    children: [
                      // Notification bell with unread counter and dropdown
                      NotificationBell(
                        onOpenAll: () =>
                            Navigator.pushNamed(context, '/notifications'),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            (() {
                              final w = MediaQuery.of(context).size.width;
                              final isTiny = w < 360;
                              if (!isTiny) return _userName;
                              final parts = _userName.split(' ');
                              return parts.isNotEmpty ? parts.first : _userName;
                            }()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      // Person Icon
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () =>
                            Navigator.pushNamed(context, '/profile_page'),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          backgroundImage:
                              _photoUrl != null && _photoUrl!.isNotEmpty
                              ? NetworkImage(_photoUrl!)
                              : null,
                          child: _photoUrl == null || _photoUrl!.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 28,
                                  color: Color(0xFF6B46C1),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                          return Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTiny ? 18 : (isMobile ? 24 : 32),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<AppSettings>(
                        stream: SettingsService.instance.stream(),
                        builder: (context, snap) {
                          final desc =
                              (snap.data != null &&
                                  snap.data!.platformDescription.isNotEmpty)
                              ? snap.data!.platformDescription
                              : 'مرحباً بك مجدداً! هيا بنا نتعلم شيئاً جديداً.';
                          return Text(
                            desc,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTiny ? 12 : (isMobile ? 14 : 16),
                              color: Colors.white70,
                              fontWeight: FontWeight.w300,
                            ),
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
                  controller: _searchController,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1F2937),
                  ),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن دروس، أو محتوى...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
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
          const SizedBox(height: 32),
          _buildVideoGrid(),
          const SizedBox(height: 40),
          _buildFavoritesRow(),
          const SizedBox(height: 32),
          _buildRecentVideos(),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return CategoryTabsWithSort(
      activeTab: _activeTab,
      onTabSelected: (id) {
        setState(() => _activeTab = id);
        _loadActiveCategoryName();
      },
      sortOption: _sortOption,
      onSortSelected: (opt) => setState(() => _sortOption = opt),
      categories: null,
    );
  }

  Widget _buildVideoGrid() {
    // Firestore-backed grid similar to admin dashboard
    final collection = FirebaseFirestore.instance.collection('videos');
    Query<Map<String, dynamic>> query = collection;
    // Apply base sort
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
      default: // 'latest'
        query = query.orderBy('timeAdded', descending: true);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد فيديوهات متاحة حالياً',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        

        // Client-side category filter (by categoryId or fallback by category name)
        var docs = snapshot.data!.docs.where((d) {
          if (_activeTab == 'all') return true;
          final data = d.data();
          final cid = (data['categoryId'] ?? '').toString();
          final cname = (data['category'] ?? '').toString();
          final byId = cid == _activeTab;
          final byName =
              _activeCategoryName != null && _activeCategoryName!.isNotEmpty
              ? cname == _activeCategoryName
              : false;
          return byId || byName;
        }).toList();

        // Client-side search filter (title/description contains)
        docs = docs.where((d) {
          final data = d.data();
          final title = (data['name'] ?? '').toString();
          final desc = (data['description'] ?? '').toString();
          final q = _searchQuery.trim();
          if (q.isEmpty) return true;
          final lowerQ = q.toLowerCase();
          return title.toLowerCase().contains(lowerQ) ||
              desc.toLowerCase().contains(lowerQ);
        }).toList();

        if (docs.isEmpty && _searchQuery.isNotEmpty) {
          return const Center(
            child: Text(
              'لا توجد نتائج مطابقة للبحث',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        if (docs.isEmpty && _searchQuery.isEmpty && _activeTab != 'all') {
          return const Center(
            child: Text(
              'لا توجد فيديوهات في هذا القسم بعد.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        // Favorites-only and favorites-first removed

        return ResponsiveVideoGrid(
          itemCount: docs.length,
          childAspectRatio: 1.2,
          itemBuilder: (context, index) {
            return _buildFirestoreVideoCard(docs[index]);
          },
        );
      },
    );
  }

  // Debounced search handler
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim();
      });
    });
  }

  Widget _buildFavoritesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'مفضلتك',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collectionGroup('favorites')
                .where('userId', isEqualTo: _auth.currentUser?.uid)
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final favDocs = snap.data?.docs ?? [];
              if (favDocs.isEmpty) {
                return const Center(
                  child: Text(
                    'لا توجد فيديوهات مفضلة حتى الآن',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: favDocs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final fav = favDocs[i];
                  final metaRef =
                      fav.reference.parent.parent; // video_meta/<videoKey>
                  if (metaRef == null) return const SizedBox();
                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: metaRef.get(),
                    builder: (context, metaSnap) {
                      if (!metaSnap.hasData) {
                        return _buildFavoriteSkeleton();
                      }
                      final meta = metaSnap.data!.data() ?? {};
                      final title = (meta['title'] ?? '').toString();
                      final videoUrl = (meta['videoUrl'] ?? '').toString();
                      final description = (meta['description'] ?? '')
                          .toString();
                      final thumb = _deriveYoutubeThumbnail(videoUrl);
                      return _buildFavoriteCard(
                        title: title.isEmpty ? 'فيديو' : title,
                        thumbnail: thumb,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteSkeleton() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: SizedBox(
              height: 14,
              width: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard({
    required String title,
    required String thumbnail,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: thumbnail.isNotEmpty
                    ? Image.network(thumbnail, fit: BoxFit.cover)
                    : Container(color: Colors.black12),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueWatchingCard({
    required String title,
    required String thumbnail,
    required double progress, // 0..1
    required VoidCallback onTap,
  }) {
    final pct = progress.clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: thumbnail.isNotEmpty
                        ? Image.network(thumbnail, fit: BoxFit.cover)
                        : Container(color: Colors.black12),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(0),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: pct > 0.02 ? pct : 0.02,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentVideos() {
    final service = EngagementService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'أكمل المشاهدة',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.myIncompleteProgressStream(limit: 20),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final progDocs = snap.data?.docs ?? [];
              if (progDocs.isEmpty) {
                return const Center(
                  child: Text(
                    'لا يوجد محتوى لمتابعة مشاهدته الآن',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: progDocs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = progDocs[i];
                  final metaRef =
                      p.reference.parent.parent; // video_meta/<videoKey>
                  if (metaRef == null) return _buildFavoriteSkeleton();
                  final pdata = p.data();
                  final pos = (pdata['positionSec'] is num)
                      ? (pdata['positionSec'] as num).toDouble()
                      : double.tryParse('${pdata['positionSec']}') ?? 0.0;
                  final dur = (pdata['durationSec'] is num)
                      ? (pdata['durationSec'] as num).toDouble()
                      : double.tryParse('${pdata['durationSec']}') ?? 0.0;
                  final progress = (dur > 0)
                      ? (pos / dur).clamp(0.0, 1.0)
                      : 0.0;
                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: metaRef.get(),
                    builder: (context, metaSnap) {
                      if (!metaSnap.hasData) {
                        return _buildFavoriteSkeleton();
                      }
                      final meta = metaSnap.data!.data() ?? {};
                      final title = (meta['title'] ?? '').toString();
                      final videoUrl = (meta['videoUrl'] ?? '').toString();
                      final description = (meta['description'] ?? '')
                          .toString();
                      final thumbFromDoc = (meta['thumbnailUrl'] ?? '')
                          .toString();
                      final thumb = thumbFromDoc.isNotEmpty
                          ? thumbFromDoc
                          : _deriveYoutubeThumbnail(videoUrl);
                      return _buildContinueWatchingCard(
                        title: title.isEmpty ? 'فيديو' : title,
                        thumbnail: thumb,
                        progress: progress,
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
              );
            },
          ),
        ),
      ],
    );
  }
}
