import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:educational_platform/components/add_video_dialog.dart';
import 'package:educational_platform/services/video_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/homePages/admin_video_details_page.dart';
import 'dart:async';
import 'package:educational_platform/components/shared_video_widgets.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:educational_platform/services/engagement_service.dart';

class ManageVideosPage extends StatefulWidget {
  const ManageVideosPage({super.key});

  @override
  State<ManageVideosPage> createState() => _ManageVideosPageState();
}

class _ManageVideosPageState extends State<ManageVideosPage> {
  String? _userPhotoUrl;
  String _activeTab = 'all';
  String?
  _activeCategoryName; // human-readable name for filtering by 'category'
  final ScrollController _scrollController = ScrollController();

  final VideoService _videoService = VideoService();

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Legacy hardcoded categories removed in favor of Firestore-driven categories

  void _showAddVideoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const AddVideoDialog();
      },
    );
  }

  Widget _buildResponsiveActions({
    required BuildContext context,
    required bool isMobile,
    required bool allowGuest,
    required VoidCallback onDetails,
    required VoidCallback onEdit,
    required VoidCallback onToggleGuest,
    required VoidCallback onDelete,
  }) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final maxW = constraints.maxWidth;
      // Ultra narrow: use compact icon row
      if (maxW < 360) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: [
                _actionIcon('تفاصيل', Icons.info_outline, Colors.blue, onDetails),
                _actionIcon('تعديل', Icons.edit, Colors.amber, onEdit),
                _actionIcon(
                  allowGuest ? 'إلغاء الإتاحة للزوار' : 'إتاحة للزوار',
                  allowGuest ? Icons.public_off : Icons.public,
                  allowGuest ? Colors.red : Colors.green,
                  onToggleGuest,
                ),
                _actionIcon('حذف', Icons.delete, Colors.red, onDelete),
              ],
            ),
          ),
        );
      }
      // Mobile/tablet: use Wrap with small pill buttons to avoid overflow
      if (maxW < 700) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _actionPill('تفاصيل', Colors.blue, onDetails),
                _actionPill('تعديل', Colors.amber, onEdit),
                _actionPill(
                  allowGuest ? 'إلغاء الإتاحة للزوار' : 'إتاحة للزوار',
                  allowGuest ? Colors.red : Colors.green,
                  onToggleGuest,
                ),
                _actionPill('حذف', Colors.red, onDelete),
              ],
            ),
          ),
        );
      }
      // Wide screens: row with evenly spaced pill buttons
      return Align(
        alignment: Alignment.centerLeft,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Flexible(child: _actionPill('تفاصيل', Colors.blue, onDetails)),
              const SizedBox(width: 8),
              Flexible(child: _actionPill('تعديل', Colors.amber, onEdit)),
              const SizedBox(width: 8),
              Flexible(
                child: _actionPill(
                  allowGuest ? 'إلغاء الإتاحة للزوار' : 'إتاحة للزوار',
                  allowGuest ? Colors.red : Colors.green,
                  onToggleGuest,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _actionPill('حذف', Colors.red, onDelete)),
            ],
          ),
        ),
      );
    });
  }

  Widget _actionIcon(
      String tooltip, IconData icon, Color color, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _actionPill(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 36,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(
          _iconForLabel(label),
          size: 18,
          color: color,
        ),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  IconData _iconForLabel(String label) {
    if (label.contains('تفاصيل')) return Icons.info_outline;
    if (label.contains('تعديل')) return Icons.edit;
    if (label.contains('حذف')) return Icons.delete;
    if (label.contains('إتاحة') || label.contains('إلغاء الإتاحة')) {
      return Icons.public;
    }
    return Icons.circle;
  }

  Future<void> _toggleGuestAvailability(String docId, bool currentlyAllowed) async {
    try {
      final updates = <String, dynamic>{
        'allowGuest': !currentlyAllowed,
      };
      if (!currentlyAllowed) {
        // When enabling guest access, ensure status is published
        updates['status'] = 'published';
        // Ensure timeAdded exists to satisfy guest query ordering
        final snap = await FirebaseFirestore.instance
            .collection('videos')
            .doc(docId)
            .get();
        final hasTime = (snap.data()?['timeAdded']) != null;
        if (!hasTime) {
          updates['timeAdded'] = FieldValue.serverTimestamp();
        }
      }
      await FirebaseFirestore.instance
          .collection('videos')
          .doc(docId)
          .set(updates, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentlyAllowed
              ? 'تم إتاحة الفيديو للزوار'
              : 'تم إلغاء إتاحة الفيديو للزوار'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الإتاحة: $e')),
      );
    }
  }

  // ملاحظة: تمت إزالة وظيفة الاستيراد من يوتيوب حسب الطلب

  Future<void> _showEditVideoDialog(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final nameController = TextEditingController(
      text: (data['name'] ?? '').toString(),
    );
    final descController = TextEditingController(
      text: (data['description'] ?? '').toString(),
    );
    final urlController = TextEditingController(
      text: (data['videoUrl'] ?? '').toString(),
    );
    String? selectedCategoryId = (data['categoryId'] ?? '').toString().isEmpty
        ? null
        : (data['categoryId'] ?? '').toString();
    String? selectedCategoryName = (data['category'] ?? '').toString().isEmpty
        ? null
        : (data['category'] ?? '').toString();
    String videoType = (data['videoType'] ?? 'free').toString();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('تعديل الفيديو'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'العنوان'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(labelText: 'الوصف'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'رابط الفيديو (YouTube)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Video Type Dropdown
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'نوع الفيديو',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: videoType,
                        items: const [
                          DropdownMenuItem(value: 'free', child: Text('مجاني')),
                          DropdownMenuItem(value: 'paid', child: Text('مدفوع')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              videoType = val;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'الفئة',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('categories')
                            .orderBy('name')
                            .snapshots(),
                        builder: (context, snapshot) {
                          final catDocs = snapshot.data?.docs ?? [];
                          final items = <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('بدون فئة'),
                            ),
                            ...catDocs.map((d) {
                              final name = (d.data()['name'] ?? '').toString();
                              return DropdownMenuItem<String>(
                                value: d.id,
                                child: Text(name.isEmpty ? d.id : name),
                              );
                            }),
                          ];
                          final currentVal =
                              (selectedCategoryId?.isNotEmpty ?? false)
                                  ? selectedCategoryId
                                  : '';
                          return DropdownButtonFormField<String>(
                            initialValue: currentVal,
                            items: items,
                            onChanged: (val) {
                              setState(() {
                                if (val == null || val.isEmpty) {
                                  selectedCategoryId = null;
                                  selectedCategoryName = null;
                                } else {
                                  selectedCategoryId = val;
                                  final match = catDocs.firstWhere((d) => d.id == val, orElse: () => catDocs.first);
                                  selectedCategoryName = (match.data()['name'] ?? '').toString();
                                }
                              });
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final desc = descController.text.trim();
                    final url = urlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    try {
                      await _videoService.updateVideo(
                        docId: docId,
                        name: name,
                        description: desc,
                        videoUrl: url,
                        categoryId: selectedCategoryId,
                        categoryName: selectedCategoryName,
                        videoType: videoType,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تحديث الفيديو بنجاح')),
                      );
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('حدث خطأ أثناء التحديث')),
                      );
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteVideo(String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الفيديو'),
          content: Text(
            'هل أنت متأكد من حذف "$name"؟ لا يمكن التراجع عن هذه العملية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _videoService.deleteVideo(docId: docId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حذف الفيديو')));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء الحذف')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    // Debounced search listener
    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        final q = _searchController.text.trim().toLowerCase();
        if (q != _searchQuery) {
          setState(() {
            _searchQuery = q;
          });
        }
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

  Future<void> _fetchUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Start with Firebase Auth photoURL as a sensible default
    String? resolvedPhotoUrl = user.photoURL;

    try {
      final DocumentSnapshot userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userData.exists && userData.data() != null) {
        final data = userData.data() as Map<String, dynamic>;
        // Prefer Firestore 'pictureUrl' (used in dashboard), then 'photoURL'; otherwise keep Auth photoURL
        final String? pictureUrl = (data['pictureUrl'] as String?)?.trim();
        final String? photoURL = (data['photoURL'] as String?)?.trim();
        if (pictureUrl != null && pictureUrl.isNotEmpty) {
          resolvedPhotoUrl = pictureUrl;
        } else if (photoURL != null && photoURL.isNotEmpty) {
          resolvedPhotoUrl = photoURL;
        }
      }
    } catch (_) {
      // Ignore errors silently; fallback already set from Auth if available
    }

    if (mounted) {
      setState(() {
        _userPhotoUrl = resolvedPhotoUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArrowScroll(
      scrollController: _scrollController,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
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
                  'إدارة الفيديوهات',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: sf(context, 22),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'تنظيم وإضافة وتحرير مقاطع الفيديو',
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
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _showAddVideoDialog,
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text(
                    'إضافة فيديو جديد',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: sf(context, 14),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(49, 41, 125, 243),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(
                        color: Color.fromARGB(255, 237, 239, 241),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 24.0),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  backgroundImage: _userPhotoUrl != null
                      ? NetworkImage(_userPhotoUrl!)
                      : null,
                  child: _userPhotoUrl == null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildCategoryTabs(),
                  const SizedBox(height: 24),
                  _buildFirestoreVideosGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        TextField(
          controller: _searchController,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: 'ابحث عن فيديو...',
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEA2A33), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTabs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('categories')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final catDocs = snapshot.data?.docs ?? [];
        // Build a list with an 'all' tab first
        final tabs = [
          {'id': 'all', 'name': 'الكل'},
          ...catDocs.map(
            (d) => {'id': d.id, 'name': (d.data()['name'] ?? '').toString()},
          ),
        ];

        // Ensure active name stays in sync
        if (_activeTab == 'all') {
          _activeCategoryName = null;
        } else {
          final match = tabs.firstWhere(
            (e) => e['id'] == _activeTab,
            orElse: () => {'id': _activeTab, 'name': ''},
          );
          _activeCategoryName = match['name'];
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: tabs.map((category) {
                final isActive = _activeTab == category['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeTab = category['id']!;
                      _activeCategoryName = category['id'] == 'all'
                          ? null
                          : category['name'];
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(left: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFEA2A33)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      (category['name'] as String).isEmpty
                          ? (category['id'] as String)
                          : (category['name'] as String),
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : const Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: sf(context, 14),
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

  Widget _buildFirestoreVideosGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('videos')
          .orderBy('timeAdded', descending: true)
          .snapshots(),
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
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد فيديوهات مضافة بعد',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        // Client-side filtering by category via either categoryId or category name
        final filteredDocs = _activeTab == 'all'
            ? docs
            : docs.where((d) {
                final data = d.data();
                final catId = (data['categoryId'] ?? '').toString();
                final catName = (data['category'] ?? '').toString();
                return catId == _activeTab ||
                    (_activeCategoryName != null &&
                        catName == _activeCategoryName);
              }).toList();

        // Apply client-side search filtering by name/description/category (case-insensitive)
        List<QueryDocumentSnapshot<Map<String, dynamic>>> displayDocs =
            filteredDocs;
        if (_searchQuery.isNotEmpty) {
          displayDocs = filteredDocs.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final desc = (data['description'] ?? '').toString().toLowerCase();
            final cat = (data['category'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery) ||
                desc.contains(_searchQuery) ||
                cat.contains(_searchQuery);
          }).toList();
        }

        if (displayDocs.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد فيديوهات لهذه الفئة حالياً',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        return ResponsiveVideoGrid(
          itemCount: displayDocs.length,
          // Make items taller by reducing aspect ratio (width/height)
          childAspectRatio: 0.95,
          itemBuilder: (context, index) {
            final doc = displayDocs[index];
            return _buildFirestoreVideoCard(doc);
          },
        );
      },
    );
  }

  Widget _buildFirestoreVideoCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final String title = (data['name'] ?? '').toString();
    final String description = (data['description'] ?? '').toString();
    final String videoUrl = (data['videoUrl'] ?? '').toString();
    final String videoType = (data['videoType'] ?? 'free').toString();
    final bool allowGuest = (data['allowGuest'] ?? false) == true;
    final String thumbnailFromDoc = (data['thumbnailUrl'] ?? '').toString();
    final String thumbnailUrl = thumbnailFromDoc.isNotEmpty
        ? thumbnailFromDoc
        : _deriveYoutubeThumbnail(videoUrl);
    final String videoKey = EngagementService.instance.videoKeyFromUrl(
      videoUrl,
    );
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/run_videos',
          arguments: {
            'title': title.isEmpty ? 'بدون عنوان' : title,
            'videoUrl': videoUrl,
            'description': description.isEmpty ? null : description,
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
                  thumbnailUrl.isNotEmpty
                      ? Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(
                                  Icons.ondemand_video_rounded,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(
                              Icons.ondemand_video_rounded,
                              color: Colors.grey,
                              size: 48,
                            ),
                          ),
                        ),
                  Container(color: Colors.black.withValues(alpha: 0.26)),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 36,
                        color: Color(0xFFEA2A33),
                      ),
                    ),
                  ),
                  // Type badge top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: videoType == 'paid'
                            ? Colors.amber.shade700
                            : Colors.green.shade600,
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
                  // Guest availability badge top-left (only if enabled)
                  if (allowGuest)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669), // emerald-600
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.public, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'متاح للزوار',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Views badge bottom-left
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
                            stream: EngagementService.instance.viewsStream(
                              videoKey,
                            ),
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
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? 'بدون عنوان' : title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: sf(context, 16),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.isEmpty ? 'لا يوجد وصف' : description,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: sf(context, 14),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    _buildResponsiveActions(
                      context: context,
                      isMobile: isMobile,
                      allowGuest: allowGuest,
                      onDetails: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminVideoDetailsPage(
                              title: title.isEmpty ? 'بدون عنوان' : title,
                              videoUrl: videoUrl,
                              description:
                                  description.isEmpty ? null : description,
                            ),
                          ),
                        );
                      },
                      onEdit: () => _showEditVideoDialog(doc.id, data),
                      onToggleGuest: () =>
                          _toggleGuestAvailability(doc.id, allowGuest),
                      onDelete: () => _confirmDeleteVideo(doc.id, title),
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

  String _deriveYoutubeThumbnail(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      String? id;
      if (uri.host.contains('youtu.be')) {
        // youtu.be/<id>
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
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg'; // or maxresdefault.jpg if available
    } catch (_) {
      return '';
    }
  }

  
}
