import 'package:cloud_firestore/cloud_firestore.dart';

class AppSettings {
  final String platformTitle;
  final String channelId;
  final String platformDescription;

  const AppSettings({
    required this.platformTitle,
    required this.channelId,
    required this.platformDescription,
  });

  factory AppSettings.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return AppSettings(
      platformTitle: (map['platformTitle'] ?? '').toString(),
      channelId: (map['channelId'] ?? '').toString(),
      platformDescription: (map['platformDescription'] ?? '').toString(),
    );
  }
}

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('app_config').doc('general');

  Stream<AppSettings> stream() {
    return _doc.snapshots().map((snap) => AppSettings.fromMap(snap.data()));
  }

  Future<AppSettings> getOnce() async {
    final snap = await _doc.get();
    return AppSettings.fromMap(snap.data());
  }
}
