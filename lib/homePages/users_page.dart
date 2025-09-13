import 'package:flutter/material.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool sidebarOpen = false;
  String searchQuery = '';
  int currentPage = 1;
  final int itemsPerPage = 5;
  final ScrollController _scrollController = ScrollController();
  String? _hoveredUserId; // for desktop hover actions
  Stream<List<UserData>>?
  _usersStreamCached; // cached to avoid resubscribe on rebuild

  // سيتم جلب المستخدمين فعليًا من Firestore عبر Stream
  // القائمة التالية لم تعد مستخدمة كمصدر للعرض
  final List<UserData> users = [];

  @override
  void initState() {
    super.initState();
    // Lazy init will handle caching on first access
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Lazy getter for a cached users stream
  Stream<List<UserData>> get _usersStreamSafe {
    return _usersStreamCached ??= _buildUsersStream();
  }

  Stream<List<UserData>> _buildUsersStream() {
    final col = FirebaseFirestore.instance.collection('users');
    return col.snapshots().map((snap) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final list = snap.docs.map((d) {
        final data = d.data();
        // Debug: اطبع عدد المستندات المحمّلة (يظهر في وحدة التحكم)
        // ignore: avoid_print
        print('Users loaded: ${snap.docs.length}');
        final id = d.id;
        final name = (data['name'] ?? '').toString();
        final phone = (data['phone'] ?? '').toString();
        // نخزن الدور بالإنجليزية في Firestore ونعرِضه بالعربية في الواجهة
        final roleStorage = (data['role'] ?? 'User').toString().toLowerCase();
        final avatar = (data['pictureUrl'] ?? '').toString();

        // الاستدلال على حقول الحالة في الواجهة عند عدم وجودها
        final isBanned =
            (data['isBanned'] ?? false) == true || roleStorage == 'banned';
        final isAdmin =
            (data['isAdmin'] ?? false) == true || roleStorage == 'Admin';
        final isActive = (data['isActive'] ?? true) == true;

        // createdAt قد يكون Timestamp أو نصًا محفوظًا مسبقًا
        String joinDateStr = '';
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final dt = createdAt.toDate();
          joinDateStr =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } else if (createdAt is String) {
          joinDateStr = createdAt;
        } else {
          joinDateStr = '';
        }

        // تحويل الدور للعرض بالعربية
        String displayRole;
        if (isBanned) {
          displayRole = 'محظور';
        } else if (isAdmin) {
          displayRole = 'مدير';
        } else {
          displayRole = 'مستخدم';
        }

        return UserData(
          id: id,
          name: name.isEmpty ? '—' : name,
          phone: phone,
          joinDate: joinDateStr.isEmpty ? '—' : joinDateStr,
          role: displayRole,
          isAdmin: isAdmin,
          isActive: isActive,
          isBanned: isBanned,
          // sanitize avatar: must be a valid http(s) URL, otherwise fallback to generated
          avatar:
              (avatar.isEmpty ||
                  !(avatar.startsWith('http://') ||
                      avatar.startsWith('https://')))
              ? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name.isEmpty ? 'User' : name)}&background=E5E7EB&color=111827'
              : avatar,
        );
      }).toList();
      // استبعاد حساب المستخدم الحالي من القائمة
      return list.where((u) => u.id != currentUid).toList();
    });
  }

  /*
  Future<void> _toggleBan(UserData user) async {
    final newBanned = !user.isBanned;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(newBanned ? 'تأكيد الحظر' : 'إلغاء الحظر'),
          content: Text(
            newBanned
                ? 'هل تريد حظر المستخدم "${user.name}"؟'
                : 'هل تريد إلغاء حظر المستخدم "${user.name}"؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    // تحديث محلي
    final prev = user.isBanned;
    setState(() {
      user.isBanned = newBanned;
      user.isAdmin = newBanned ? false : user.isAdmin;
      user.role = newBanned ? 'محظور' : (user.isAdmin ? 'مدير' : 'مستخدم');
    });
    try {
      final storageRole = newBanned
          ? 'banned'
          : (user.isAdmin ? 'Admin' : 'User');
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'role': storageRole,
        'isBanned': newBanned,
        if (newBanned) 'isAdmin': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newBanned ? 'تم حظر المستخدم' : 'تم إلغاء الحظر'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => user.isBanned = prev);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تنفيذ العملية: $e')));
      }
    }
  }
*/
  /*
  Future<void> _toggleActive(UserData user) async {
    final newActive = !user.isActive;
    // تحديث محلي سريع
    setState(() => user.isActive = newActive);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'isActive': newActive,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newActive ? 'تم تفعيل الحساب' : 'تم تعطيل الحساب'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => user.isActive = !newActive);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تحديث حالة الحساب: $e')));
      }
    }
  }
*/
  Future<void> _viewUser(UserData user) async {
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تفاصيل المستخدم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(user.avatar),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          user.phone,
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _kv('الدور', user.role),
              _kv(
                'الحالة',
                user.isBanned ? 'محظور' : (user.isActive ? 'نشط' : 'غير نشط'),
              ),
              _kv('تاريخ الانضمام', user.joinDate),
              _kv('معرّف المستند', user.id),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Color(0xFF6B7280))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.left,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
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
                'إدارة المستخدمين',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: sf(context, 18),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'عرض وتصفية وتعديل بيانات المستخدمين',
                style: TextStyle(
                  fontSize: sf(context, 12),
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
            Builder(
              builder: (context) {
                final w = MediaQuery.of(context).size.width;
                final isTiny = w < 360;
                final isMobile = w < 600;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/signup');
                    },
                    icon: Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: sd(context, isTiny ? 16 : (isMobile ? 18 : 20)),
                    ),
                    label: Text(
                      'إضافة مستخدم',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: sf(
                          context,
                          isTiny ? 11 : (isMobile ? 12 : 14),
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                      padding: EdgeInsets.symmetric(
                        horizontal: isTiny ? 10 : (isMobile ? 14 : 18),
                        vertical: isTiny ? 8 : (isMobile ? 10 : 12),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: ArrowScroll(
          scrollController: _scrollController,
          child: Stack(
            children: [
              // Main Content
              Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildMainContent()),
                ],
              ),
              // Sidebar
              if (sidebarOpen) _buildSidebarOverlay(),
              if (sidebarOpen) _buildSidebar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: sp(context, 24),
        vertical: sp(context, 16),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => sidebarOpen = true),
            icon: const Icon(Icons.menu, color: Color(0xFF6B7280)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: TextField(
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    suffixIcon:
                        const Icon(Icons.search, color: Color(0xFF9CA3AF)),
                  ),
                  onChanged: (value) => setState(() => searchQuery = value),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: EdgeInsets.all(sp(context, 24)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<UserData>>(
                stream: _usersStreamSafe,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'حدث خطأ أثناء جلب المستخدمين',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final data = snapshot.data ?? [];
                  if (data.isEmpty) {
                    return Column(
                      children: [
                        const SizedBox(height: 24),
                        const Text(
                          'لا توجد بيانات مستخدمين حالياً',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'تأكد من أنك مسجّل الدخول ولديك صلاحية قراءة مجموعة users.\nوتحقق من أن اسم المجموعة هو users بالضبط.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  }

                  // التصفية حسب البحث
                  final q = searchQuery.trim();
                  final filtered = q.isEmpty
                      ? data
                      : data
                            .where(
                              (u) =>
                                  u.name.contains(q) ||
                                  u.phone.contains(q) ||
                                  u.role.contains(q),
                            )
                            .toList();

                  final total = filtered.length;
                  final totalPages = (total / itemsPerPage).ceil().clamp(
                    1,
                    9999,
                  );
                  if (currentPage > totalPages) currentPage = totalPages;
                  final start = ((currentPage - 1) * itemsPerPage).clamp(
                    0,
                    total,
                  );
                  final end = (start + itemsPerPage).clamp(0, total);
                  final visible = filtered.sublist(start, end);

                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: _buildUsersTableFrom(visible),
                        ),
                      ),
                      _buildPagination(
                        total: total,
                        start: start,
                        end: end,
                        totalPages: totalPages,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTableFrom(List<UserData> users) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    if (isMobile) {
      // Mobile: name + actions only
      return Column(children: [...users.map((u) => _buildMobileUserItem(u))]);
    } else {
      // Desktop: 4 columns header and rows; actions appear on hover
      return Column(
        children: [
          _buildDesktopHeader(),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ...users.map((u) => _buildDesktopRow(u)),
        ],
      );
    }
  }

  Widget _buildDesktopHeader() {
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: EdgeInsets.symmetric(
        horizontal: sp(context, 16),
        vertical: sp(context, 12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'اسم المستخدم',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                fontSize: sf(context, 14),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'رقم الهاتف',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                fontSize: sf(context, 14),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'تاريخ الانضمام',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                fontSize: sf(context, 14),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الدور',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                fontSize: sf(context, 14),
              ),
            ),
          ),
          SizedBox(
            width: _actionsWidth(context), // space for hover actions (matches row)
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopRow(UserData user) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final hovered = _hoveredUserId == user.id;
    final screenW = MediaQuery.of(context).size.width;
    final actionIconSize = screenW < 900 ? 14.0 : 16.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredUserId = user.id),
      onExit: (_) => setState(() => _hoveredUserId = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: hovered ? const Color(0xFFF9FAFB) : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: sp(context, 16),
          vertical: sp(context, 12),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: _buildUserCell(user)),
            Expanded(flex: 2, child: _buildPhoneCell(user.phone)),
            Expanded(flex: 2, child: _buildDateCell(user.joinDate)),
            Expanded(flex: 2, child: _buildRoleChip(user)),
            SizedBox(
              width: _actionsWidth(context),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: hovered ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !hovered,
                    child: MouseRegion(
                      onEnter: (_) {
                        if (_hoveredUserId != user.id) {
                          setState(() => _hoveredUserId = user.id);
                        }
                      },
                      onExit: (_) {
                        // Do nothing here; parent row MouseRegion will handle exit when truly leaving the row
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _viewUser(user),
                            icon: Icon(
                              Icons.visibility_outlined,
                              color: const Color(0xFF4B5563),
                              size: actionIconSize,
                            ),
                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                            tooltip: 'تفاصيل',
                          ),
                          IconButton(
                            onPressed: () => _editUser(user),
                            icon: Icon(
                              Icons.edit_outlined,
                              color: const Color(0xFF4B5563),
                              size: actionIconSize,
                            ),
                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                            tooltip: 'تعديل',
                          ),
                          if (user.id != currentUid)
                            IconButton(
                              onPressed: () => _deleteUser(user),
                              icon: Icon(
                                Icons.delete_outline,
                                color: const Color(0xFFEF4444),
                                size: actionIconSize,
                              ),
                              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                              tooltip: 'حذف',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCell(UserData user) {
    final w = MediaQuery.of(context).size.width;
    final avatarRadius = w < 900 ? 18.0 : 22.0;
    return Row(
      children: [
        CircleAvatar(
          radius: avatarRadius,
          backgroundImage: NetworkImage(user.avatar),
          backgroundColor: const Color(0xFFF3F4F6),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.isBanned
                    ? 'حساب محظور'
                    : (user.isActive ? 'مستخدم نشط' : 'مستخدم غير نشط'),
                style: TextStyle(
                  fontSize: 11,
                  color: user.isBanned ? Colors.red : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneCell(String phone) {
    return Text(
      phone,
      style: TextStyle(
        color: const Color(0xFF6B7280),
        fontSize: sf(context, 14),
      ),
    );
  }

  Widget _buildDateCell(String date) {
    return Text(
      date,
      style: TextStyle(
        color: const Color(0xFF6B7280),
        fontSize: sf(context, 14),
      ),
    );
  }

  Widget _buildRoleChip(UserData user) {
    Color backgroundColor;
    Color textColor;

    if (user.isBanned) {
      backgroundColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFF991B1B);
    } else if (user.role == 'مدير') {
      backgroundColor = const Color(0xFFEDE9FE);
      textColor = const Color(0xFF6B21A8);
    } else {
      backgroundColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        user.role,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: sf(context, 12),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // Inline actions (hover on desktop)
  Widget _buildInlineActions(UserData user) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final w = MediaQuery.of(context).size.width;
    final iconSize = w < 700 ? 16.0 : 18.0;
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          onPressed: () => _viewUser(user),
          icon: Icon(
            Icons.visibility_outlined,
            color: const Color(0xFF6B7280),
            size: iconSize,
          ),
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          tooltip: 'تفاصيل',
        ),
        IconButton(
          onPressed: () => _editUser(user),
          icon: Icon(
            Icons.edit_outlined,
            color: const Color(0xFF6B7280),
            size: iconSize,
          ),
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          tooltip: 'تعديل',
        ),
        if (user.id != currentUid)
          IconButton(
            onPressed: () => _deleteUser(user),
            icon: Icon(
              Icons.delete_outline,
              color: const Color(0xFFEF4444),
              size: iconSize,
            ),
            padding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            tooltip: 'حذف',
          ),
      ],
    );
  }

  double _actionsWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 700) return 120;
    if (w < 900) return 150;
    return 200;
  }

  // Mobile list item: name + always visible actions (view, edit, delete)
  Widget _buildMobileUserItem(UserData user) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: sp(context, 12),
        vertical: sp(context, 10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(user.avatar),
            backgroundColor: const Color(0xFFF3F4F6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildInlineActions(user),
        ],
      ),
    );
  }

  Future<void> _deleteUser(UserData user) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (user.id == currentUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكنك حذف حسابك الشخصي.')),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
            'هل أنت متأكد من حذف المستخدم "${user.name}"؟ لا يمكن التراجع.',
          ),
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
      ),
    );
    if (ok != true) return;
    try {
      // Call Cloud Function to delete the user from Firebase Auth and Firestore
      final callable = FirebaseFunctions.instance.httpsCallable(
        'deleteUserByUid',
      );
      await callable.call({'uid': user.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المستخدم من النظام')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل حذف المستخدم: $e')));
      }
    }
  }

  Future<void> _editUser(UserData user) async {
    final nameCtrl = TextEditingController(
      text: user.name == '—' ? '' : user.name,
    );
    final phoneCtrl = TextEditingController(text: user.phone);
    String role = user.role;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل المستخدم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role.isEmpty ? 'مستخدم' : role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: const [
                  DropdownMenuItem(value: 'مستخدم', child: Text('مستخدم')),
                  DropdownMenuItem(value: 'مدير', child: Text('مدير')),
                  DropdownMenuItem(value: 'محظور', child: Text('محظور')),
                ],
                onChanged: (v) => role = v ?? 'مستخدم',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      // تحويل قيمة الدور للغة التخزين في Firestore
      String storageRole;
      bool isAdmin = false;
      bool isBanned = false;
      switch ((role).trim()) {
        case 'مدير':
          storageRole = 'Admin';
          isAdmin = true;
          break;
        case 'محظور':
          storageRole = 'banned';
          isBanned = true;
          break;
        case 'مستخدم':
        default:
          storageRole = 'User';
      }

      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'role': storageRole,
        'isAdmin': isAdmin,
        'isBanned': isBanned,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
      }
    }
  }

  Widget _buildPagination({
    required int total,
    required int start,
    required int end,
    required int totalPages,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'عرض ${total == 0 ? 0 : (start + 1)}-$end من $total مستخدم',
              style: TextStyle(
                fontSize: sf(context, 14),
                color: Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            runSpacing: 4,
            children: [
              IconButton(
                onPressed: currentPage > 1
                    ? () => setState(() => currentPage--)
                    : null,
                icon: Icon(Icons.chevron_right, size: sd(context, 20)),
              ),
              ...List.generate(totalPages, (index) {
                final pageNum = index + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: pageNum == currentPage
                      ? Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: sd(context, 16),
                            vertical: sd(context, 8),
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6D28D9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$pageNum',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: sf(context, 14),
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: () =>
                              setState(() => currentPage = pageNum),
                          child: Text(
                            '$pageNum',
                            style: TextStyle(
                              color: const Color(0xFF6B7280),
                              fontSize: sf(context, 14),
                            ),
                          ),
                        ),
                );
              }),
              IconButton(
                onPressed: currentPage < totalPages
                    ? () => setState(() => currentPage++)
                    : null,
                icon: Icon(Icons.chevron_left, size: sd(context, 20)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarOverlay() {
    return GestureDetector(
      onTap: () => setState(() => sidebarOpen = false),
      child: Container(color: Colors.black.withValues(alpha: 0.3)),
    );
  }

  Widget _buildSidebar() {
    final screenWidth = MediaQuery.of(context).size.width;
    double sidebarWidth;
    if (screenWidth < 360) {
      sidebarWidth = screenWidth * 0.85; // very small phones
    } else if (screenWidth < 600) {
      sidebarWidth = screenWidth * 0.72; // small phones
    } else if (screenWidth < 900) {
      sidebarWidth = 320; // tablets / small desktops
    } else {
      sidebarWidth = 360; // large desktops
    }
    // Clamp to sensible bounds like admin
    sidebarWidth = sidebarWidth.clamp(240.0, 420.0);

    return Positioned(
      top: 0,
      right: 0,
      height: MediaQuery.of(context).size.height,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(-4, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إدارة المستخدمين',
                        style: TextStyle(
                          fontSize: sf(context, 20),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6D28D9),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => sidebarOpen = false),
                        icon: Icon(
                          Icons.close,
                          color: const Color(0xFF6B7280),
                          size: sd(context, 20),
                        ),
                        tooltip: 'إغلاق القائمة',
                      ),
                    ],
                  ),
                ),
                // Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildSidebarItem(
                        Icons.dashboard_outlined,
                        'لوحة التحكم',
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushReplacementNamed(
                            context,
                            '/admin_dashboard',
                          );
                        },
                      ),
                      _buildSidebarItem(
                        Icons.school_outlined,
                        'الدورات',
                        false,
                      ),
                      _buildSidebarItem(
                        Icons.movie_outlined,
                        'الفيديوهات',
                        false,
                      ),
                      _buildSidebarItem(
                        Icons.group_outlined,
                        'إدارة المستخدمين',
                        true,
                      ),
                      _buildSidebarItem(
                        Icons.bar_chart_outlined,
                        'التحليلات',
                        false,
                      ),
                      _buildSidebarItem(
                        Icons.settings_outlined,
                        'الإعدادات',
                        false,
                      ),
                      const SizedBox(height: 12),
                      _buildSidebarItem(
                        Icons.person_outlined,
                        'الملف الشخصي',
                        false,
                      ),
                      _buildSidebarItem(
                        Icons.logout,
                        'تسجيل الخروج',
                        false,
                        isLogout: true,
                      ),
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

  Widget _buildSidebarItem(
    IconData icon,
    String title,
    bool isActive, {
    bool isLogout = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive
              ? const Color(0xFF6D28D9)
              : isLogout
              ? Colors.red
              : const Color(0xFF9CA3AF),
          size: sd(context, 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive
                ? const Color(0xFF6D28D9)
                : isLogout
                ? Colors.red
                : const Color(0xFF374151),
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isActive ? const Color(0xFFEDE9FE) : null,
        onTap: onTap ?? () {},
      ),
    );
  }
}

class UserData {
  String id;
  String name;
  String phone;
  String joinDate;
  String role;
  bool isAdmin;
  bool isActive;
  bool isBanned;
  String avatar;

  UserData({
    required this.id,
    required this.name,
    required this.phone,
    required this.joinDate,
    required this.role,
    required this.isAdmin,
    required this.isActive,
    this.isBanned = false,
    required this.avatar,
  });
}
