import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EngagementService {
  EngagementService._();
  static final instance = EngagementService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Build a stable key from video URL
  String videoKeyFromUrl(String videoUrl) {
    final bytes = utf8.encode(videoUrl.trim());
    return sha1.convert(bytes).toString();
  }

  DocumentReference<Map<String, dynamic>> _videoMetaRef(String videoKey) {
    return _db.collection('video_meta').doc(videoKey);
  }

  Future<void> ensureVideoMeta({
    required String videoKey,
    required String title,
    required String videoUrl,
    String? description,
  }) async {
    await _videoMetaRef(videoKey).set({
      'title': title,
      'videoUrl': videoUrl,
      'description': description,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Views
  Stream<int> viewsStream(String videoKey) {
    return _videoMetaRef(videoKey).snapshots().map((d) {
      final v = d.data()?['views'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    });
  }

  Future<void> incrementViews(String videoKey) async {
    await _videoMetaRef(videoKey).set({
      'views': FieldValue.increment(1),
      'lastViewAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Favorites
  CollectionReference<Map<String, dynamic>> _favoritesCol(String videoKey) =>
      _videoMetaRef(videoKey).collection('favorites');

  Future<bool> isFavorite(String videoKey) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _favoritesCol(videoKey).doc(uid).get();
    return snap.exists;
  }

  Stream<bool> favoriteStream(String videoKey) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream<bool>.empty();
    return _favoritesCol(videoKey).doc(uid).snapshots().map((d) => d.exists);
  }

  Future<void> toggleFavorite(String videoKey) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final profile = await _resolveCurrentUserProfile();
    final ref = _favoritesCol(videoKey).doc(uid);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'userId': uid,
        'name': profile['name'],
        'photoUrl': profile['photoUrl'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Comments
  CollectionReference<Map<String, dynamic>> _commentsCol(String videoKey) =>
      _videoMetaRef(videoKey).collection('comments');

  Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(String videoKey) {
    return _commentsCol(
      videoKey,
    ).orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> addComment(String videoKey, String text) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;
    final profile = await _resolveCurrentUserProfile();
    await _commentsCol(videoKey).add({
      'userId': user.uid,
      'name': profile['name'] ?? 'مستخدم',
      'photoUrl': profile['photoUrl'],
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateComment(
    String videoKey,
    String commentId,
    String newText,
  ) async {
    final uid = _auth.currentUser?.uid;
    final trimmed = newText.trim();
    if (uid == null || trimmed.isEmpty) return;
    final ref = _commentsCol(videoKey).doc(commentId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    if (data['userId'] != uid) {
      throw Exception('غير مصرح لك بتحديث هذا التعليق');
    }
    await ref.update({
      'text': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment(String videoKey, String commentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _commentsCol(videoKey).doc(commentId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    if (data['userId'] != uid) {
      throw Exception('غير مصرح لك بحذف هذا التعليق');
    }
    await ref.delete();
  }

  // Admin comment delete (no ownership check)
  Future<void> adminDeleteComment(String videoKey, String commentId) async {
    await _commentsCol(videoKey).doc(commentId).delete();
  }

  // Ratings
  CollectionReference<Map<String, dynamic>> _ratingsCol(String videoKey) =>
      _videoMetaRef(videoKey).collection('ratings');

  Stream<double> averageRatingStream(String videoKey) {
    return _ratingsCol(videoKey).snapshots().map((qs) {
      if (qs.docs.isEmpty) return 0.0;
      final values = qs.docs
          .map((d) => (d.data()['value'] as num?)?.toDouble() ?? 0.0)
          .toList();
      if (values.isEmpty) return 0.0;
      final sum = values.reduce((a, b) => a + b);
      return double.parse((sum / values.length).toStringAsFixed(1));
    });
  }

  Stream<int> ratingsCountStream(String videoKey) {
    return _ratingsCol(videoKey).snapshots().map((qs) => qs.docs.length);
  }

  Future<int?> myRating(String videoKey) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _ratingsCol(videoKey).doc(uid).get();
    if (!snap.exists) return null;
    final v = snap.data()?['value'];
    return v is int ? v : (v is num ? v.toInt() : null);
  }

  Future<void> setRating(String videoKey, int value) async {
    if (value < 1 || value > 5) return;
    final user = _auth.currentUser;
    if (user == null) return;
    final profile = await _resolveCurrentUserProfile();
    await _ratingsCol(videoKey).doc(user.uid).set({
      'userId': user.uid,
      'value': value,
      'name': profile['name'],
      'photoUrl': profile['photoUrl'],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Admin delete a specific user's rating
  Future<void> adminDeleteRating(String videoKey, String userId) async {
    await _ratingsCol(videoKey).doc(userId).delete();
  }

  // Admin delete rating by Firestore document ID (covers legacy docs not keyed by userId)
  Future<void> adminDeleteRatingByDocId(String videoKey, String docId) async {
    await _ratingsCol(videoKey).doc(docId).delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> favoritesStream(String videoKey) {
    return _favoritesCol(videoKey).snapshots();
  }

  // Admin remove favorite by user
  Future<void> adminDeleteFavorite(String videoKey, String userId) async {
    await _favoritesCol(videoKey).doc(userId).delete();
  }

  // Admin delete favorite by Firestore document ID (covers legacy docs not keyed by userId)
  Future<void> adminDeleteFavoriteByDocId(String videoKey, String docId) async {
    await _favoritesCol(videoKey).doc(docId).delete();
  }

  // Ratings stream for admin listing
  Stream<QuerySnapshot<Map<String, dynamic>>> ratingsStream(String videoKey) {
    return _ratingsCol(videoKey).snapshots();
  }

  // Progress (watch history)
  CollectionReference<Map<String, dynamic>> _progressCol(String videoKey) =>
      _videoMetaRef(videoKey).collection('progress');

  Future<void> updateWatchProgress(
    String videoKey, {
    required int positionSec,
    int? durationSec,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _progressCol(videoKey).doc(user.uid).set({
      'userId': user.uid,
      'positionSec': positionSec,
      if (durationSec != null) 'durationSec': durationSec,
      'completed': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markCompleted(String videoKey) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _progressCol(videoKey).doc(user.uid).set({
      'userId': user.uid,
      'completed': true,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // User's incomplete progress across all videos
  Stream<QuerySnapshot<Map<String, dynamic>>> myIncompleteProgressStream({int limit = 20}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collectionGroup('progress')
        .where('userId', isEqualTo: uid)
        .where('completed', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // PDF management
  Future<void> setPdfUrl(String videoKey, String pdfUrl) async {
    await _videoMetaRef(videoKey).set({
      'pdfUrl': pdfUrl,
      'pdfUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearPdfUrl(String videoKey) async {
    await _videoMetaRef(videoKey).set({
      'pdfUrl': FieldValue.delete(),
      'pdfUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Try to resolve current user's display name and photo
  Future<Map<String, String?>> _resolveCurrentUserProfile() async {
    final u = _auth.currentUser;
    String? name = u?.displayName;
    String? photo = u?.photoURL;
    if ((name == null || name.isEmpty) || (photo == null || photo.isEmpty)) {
      final uid = u?.uid;
      if (uid != null) {
        // Try common collections and field names
        final candidates = <DocumentReference<Map<String, dynamic>>>[
          _db.collection('users').doc(uid),
          _db.collection('profiles').doc(uid),
        ];
        for (final ref in candidates) {
          try {
            final snap = await ref.get();
            if (snap.exists) {
              final d = snap.data()!;
              name =
                  name ??
                  (d['name'] ?? d['displayName'] ?? d['fullName'])?.toString();
              photo =
                  photo ??
                  (d['photoUrl'] ?? d['pictureUrl'] ?? d['avatar'] ?? d['imageUrl'])?.toString();
              if (name != null && photo != null) break;
            }
          } catch (_) {}
        }
      }
    }
    name = (name == null || name.isEmpty) ? 'مستخدم' : name;
    return {'name': name, 'photoUrl': photo};
  }
}
