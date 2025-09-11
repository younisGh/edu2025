import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/services/notification_service.dart';
import 'package:educational_platform/utils/typography.dart';

class NotificationBell extends StatelessWidget {
  final VoidCallback? onOpenAll;
  const NotificationBell({super.key, this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.instance;

    return StreamBuilder<int>(
      stream: service.unreadCountStream(),
      initialData: 0,
      builder: (context, countSnap) {
        final count = countSnap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            PopupMenuButton<_MenuAction>(
              icon: Icon(Icons.notifications_none, size: sd(context, 24)),
              tooltip: 'الإشعارات',
              onSelected: (action) {
                if (action == _MenuAction.openAll) {
                  onOpenAll?.call();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<_MenuAction>(
                  enabled: false,
                  child: SizedBox(width: 320, child: _UnreadList(limit: 8)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_MenuAction>(
                  value: _MenuAction.openAll,
                  child: Text('عرض جميع الإشعارات'),
                ),
              ],
            ),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: sf(context, 11),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _MenuAction { openAll }

class _UnreadList extends StatelessWidget {
  final int limit;
  const _UnreadList({required this.limit});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.instance;
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: service.unreadNotificationsStream(limit: limit),
      builder: (context, snap) {
        final docs = snap.data ?? const [];
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('لا توجد إشعارات غير مقروءة'),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final title = (d['title'] ?? '').toString();
              final body = (d['body'] ?? '').toString();
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  Icons.notifications_active,
                  color: Colors.amber,
                  size: sd(context, 18),
                ),
                title: Text(
                  title.isEmpty ? 'إشعار' : title,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: body.isNotEmpty
                    ? Text(body, maxLines: 2, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: TextButton(
                  onPressed: () => NotificationService.instance.markAsRead(id),
                  child: const Text('تعليم كمقروء'),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
