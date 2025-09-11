import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/services/notification_service.dart';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:educational_platform/utils/typography.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationService.instance;
  static const _pageSize = 20;

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final q = _service.allNotificationsQuery(pageSize: _pageSize);
      final snap = await q.get();
      _items
        ..clear()
        ..addAll(snap.docs);
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == _pageSize;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
    });
    try {
      var q = _service.allNotificationsQuery(pageSize: _pageSize);
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        _items.addAll(snap.docs);
        _lastDoc = snap.docs.last;
      }
      _hasMore = snap.docs.length == _pageSize;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAll() async {
    await _service.markAllAsRead();
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الإشعارات', style: TextStyle(fontSize: sf(context, 18))),
          actions: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = MediaQuery.of(context).size.width;
                final isNarrow =
                    width < 360; // collapse text on very small widths
                if (isNarrow) {
                  return IconButton(
                    tooltip: 'تعليم الكل كمقروء',
                    onPressed: _markAll,
                    icon: Icon(Icons.done_all, size: sd(context, 20)),
                  );
                }
                return TextButton.icon(
                  onPressed: _markAll,
                  icon: Icon(Icons.done_all, size: sd(context, 20)),
                  label: const Text('تعليم الكل كمقروء'),
                );
              },
            ),
            PopupMenuButton<String>(
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete_read',
                  child: Text('حذف جميع المقروء'),
                ),
              ],
              onSelected: (v) async {
                if (v == 'delete_read') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد الحذف'),
                      content: const Text(
                        'هل تريد حذف جميع الإشعارات المقروءة؟ لا يمكن التراجع.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('حذف'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  final count = await _service.deleteAllRead();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        count == 0
                            ? 'لا يوجد إشعارات مقروءة للحذف'
                            : 'تم حذف $count من الإشعارات المقروءة',
                      ),
                    ),
                  );
                  await _loadInitial();
                }
              },
            ),
          ],
        ),
        body: ArrowScroll(
          scrollController: _scrollController,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: RefreshIndicator(
              onRefresh: _loadInitial,
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    // Load more indicator
                    if (_hasMore) {
                      if (!_isLoading) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _loadMore(),
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  }
                  final doc = _items[index];
                  final data = doc.data();
                  final title = (data['title'] ?? 'إشعار').toString();
                  final body = (data['body'] ?? '').toString();
                  final read = data['read'] == true;
                  final ts = data['createdAt'];
                  DateTime? createdAt;
                  if (ts is Timestamp) createdAt = ts.toDate();

                  // Number badge (1-based)
                  final number = index + 1;
                  return Container(
                    decoration: BoxDecoration(
                      color: read ? Colors.white : const Color(0xFFFFFBEB),
                    ),
                    child: ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: read
                                ? Colors.grey.shade300
                                : Colors.amber,
                            foregroundColor: Colors.black,
                            child: Text(
                              '$number',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!read)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontWeight: read
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (body.isNotEmpty) Text(body, softWrap: true),
                          if (createdAt != null)
                            Text(
                              _formatTime(createdAt),
                              style: TextStyle(
                                fontSize: sf(context, 12),
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (!read)
                            TextButton(
                              onPressed: () => _service.markAsRead(doc.id),
                              child: const Text('كمقروء'),
                            ),
                          IconButton(
                            tooltip: 'حذف',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('حذف الإشعار'),
                                  content: const Text(
                                    'هل تريد حذف هذا الإشعار؟',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('إلغاء'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('حذف'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await _service.deleteNotification(doc.id);
                                if (!mounted) return;
                                setState(() {
                                  _items.removeAt(index);
                                });
                              }
                            },
                            icon: Icon(Icons.delete_outline, size: sd(context, 20)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return '${diff.inHours} ساعة';
    return '${diff.inDays} يوم';
  }
}
