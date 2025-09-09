import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// NotificationService centralizes all notification-related client logic.
///
/// Responsibilities:
/// - Request FCM permissions (web/desktop/mobile as supported) and obtain token
/// - Persist FCM token under the current user's document
/// - Provide streams for unread counts and unread notifications
/// - Provide queries for all notifications with pagination
/// - Mark notifications as read (single / all)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _fcm = FirebaseMessaging.instance;
  // Use region-specific instance to match deployed region and avoid CORS issues on web
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// Call once after login to register token and set up handlers.
  Future<void> initAndRegisterToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // On iOS/macOS/Android, request permission. On web returns granted by default (or prompts).
      await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Get or refresh token
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveUserToken(user.uid, token);
      }

      // Listen to token refreshes
      _fcm.onTokenRefresh.listen((t) => _saveUserToken(user.uid, t));

      // Optional: foreground message handler (UI layer can also handle this)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Intentionally no UI here. UI can subscribe and show in-app banners if needed.
        // This service focuses on data persistence and streams.
      });
    } catch (e) {
      // Avoid throwing to not block app start; log to Firestore only in debug if desired.
    }
  }

  Future<void> _saveUserToken(String uid, String token) async {
    final userRef = _fs.collection('users').doc(uid);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      // Store a set-like structure: array of unique tokens
      final tokens = List<String>.from((data['fcmTokens'] ?? const <dynamic>[]) as List);
      if (!tokens.contains(token)) tokens.add(token);
      tx.set(userRef, {
        'fcmTokens': tokens,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Stream unread notifications count for current user.
  /// Treats documents with missing 'read' field as unread.
  Stream<int> unreadCountStream({String? uid}) {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return const Stream<int>.empty();
    return _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .snapshots()
        .map((s) => s.docs.where((d) => d.data()['read'] != true).length);
  }

  /// Stream latest unread notifications for current user (dropdown usage).
  /// Treats documents with missing 'read' field as unread.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> unreadNotificationsStream({
    String? uid,
    int limit = 10,
  }) {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return const Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.empty();
    return _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50) // fetch more then filter client-side
        .snapshots()
        .map((s) {
          final filtered = s.docs.where((d) {
            final v = d.data()['read'];
            return v != true; // include false or missing
          }).take(limit).toList();
          return filtered;
        });
  }

  /// Query all notifications (for notifications page). Use startAfter for pagination.
  Query<Map<String, dynamic>> allNotificationsQuery({String? uid, int pageSize = 20}) {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) {
      // Return a harmless query; caller should guard against null user.
      return _fs.collection('null').limit(0);
    }
    return _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
  }

  Future<void> markAsRead(String notificationId, {String? uid}) async {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return;
    final ref = _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId);
    await ref.set({'read': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> markAllAsRead({String? uid}) async {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return;

    final batch = _fs.batch();
    final q = await _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    for (final d in q.docs) {
      batch.set(d.reference, {'read': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String notificationId, {String? uid}) async {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return;
    final ref = _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId);
    await ref.delete();
  }

  Future<int> deleteAllRead({String? uid}) async {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null) return 0;
    final q = await _fs
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: true)
        .get();
    if (q.docs.isEmpty) return 0;
    final batch = _fs.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    return q.docs.length;
  }
}

extension NotificationServiceAdmin on NotificationService {
  /// Call Cloud Function to send admin notification.
  /// When [broadcast] is true, [targetUid] is ignored and notification will be sent to all users.
  Future<void> sendAdminNotification({
    required String title,
    required String body,
    Map<String, String>? data,
    String? targetUid,
    bool broadcast = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in');
    final callable = _functions.httpsCallable('sendAdminNotification');
    await callable.call({
      'title': title,
      'body': body,
      if (data != null) 'data': data,
      if (targetUid != null && targetUid.isNotEmpty) 'targetUid': targetUid,
      'broadcast': broadcast,
    });
  }
}
