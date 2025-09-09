import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:educational_platform/services/engagement_service.dart';

class VideoService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> _uploadFile(PlatformFile file, String path) async {
    try {
      final ref = _storage.ref(path);
      UploadTask uploadTask;

      if (kIsWeb) {
        if (file.bytes != null) {
          uploadTask = ref.putData(file.bytes!);
        } else {
          throw Exception('File bytes are null on web.');
        }
      } else {
        if (file.path != null) {
          uploadTask = ref.putFile(File(file.path!));
        } else {
          throw Exception('File path is null on mobile.');
        }
      }

      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading file: $e');
      rethrow;
    }
  }

  Future<void> addVideo({
    required String name, // Changed from title
    required String description,
    required String videoUrl,
    PlatformFile? pdfFile,
    PlatformFile? videoFile, // New: allow direct video upload
    String? categoryId,
    String? categoryName,
  }) async {
    try {
      // 1. Upload video file if provided, otherwise use the given URL (e.g., YouTube)
      String finalVideoUrl = videoUrl;
      if (videoFile != null) {
        finalVideoUrl = await _uploadFile(
          videoFile,
          'videos/${DateTime.now().millisecondsSinceEpoch}_${videoFile.name}',
        );
      }

      // 2. Upload PDF file if it exists
      String? pdfUrl;
      if (pdfFile != null) {
        pdfUrl = await _uploadFile(
          pdfFile,
          'pdfs/${DateTime.now().millisecondsSinceEpoch}_${pdfFile.name}',
        );
      }

      // 3. Prepare thumbnail URL (derive from YouTube link if possible)
      final String? thumbnailUrl = _deriveYoutubeThumbnail(finalVideoUrl);

      // 4. Save video metadata to Firestore (videos collection)
      await _firestore.collection('videos').add({
        'name': name,
        'description': description,
        'videoUrl': finalVideoUrl,
        'pdfUrl': pdfUrl,
        'thumbnailUrl': thumbnailUrl,
        'timeAdded': FieldValue.serverTimestamp(),
        'views': 0,
        // Category fields (optional)
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        if (categoryName != null && categoryName.isNotEmpty)
          'category': categoryName,
        // You can add other fields like duration, etc.
      });

      // 5. Mirror minimal metadata into video_meta keyed by URL hash for engagement features
      final videoKey = EngagementService.instance.videoKeyFromUrl(
        finalVideoUrl,
      );
      await EngagementService.instance.ensureVideoMeta(
        videoKey: videoKey,
        title: name,
        videoUrl: finalVideoUrl,
        description: description,
      );
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('video_meta')
            .doc(videoKey)
            .set({
              'pdfUrl': pdfUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error adding video: $e');
      rethrow;
    }
  }

  Future<void> updateVideo({
    required String docId,
    required String name,
    required String description,
    required String videoUrl,
    String? categoryId,
    String? categoryName,
  }) async {
    try {
      final String? thumbnailUrl = _deriveYoutubeThumbnail(videoUrl);
      final payload = <String, dynamic>{
        'name': name,
        'description': description,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (categoryId != null) payload['categoryId'] = categoryId;
      if (categoryName != null) payload['category'] = categoryName;
      await _firestore.collection('videos').doc(docId).update(payload);
    } catch (e) {
      debugPrint('Error updating video: $e');
      rethrow;
    }
  }

  Future<void> deleteVideo({required String docId}) async {
    try {
      await _firestore.collection('videos').doc(docId).delete();
    } catch (e) {
      debugPrint('Error deleting video: $e');
      rethrow;
    }
  }

  // Try to derive YouTube thumbnail URL from a given video URL
  String? _deriveYoutubeThumbnail(String url) {
    if (url.isEmpty) return null;
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
      if (id == null || id.isEmpty) return null;
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    } catch (_) {
      return null;
    }
  }
}
