import 'package:flutter/material.dart';
import 'package:educational_platform/services/settings_service.dart';

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildFooter();
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.transparent,
      child: StreamBuilder<AppSettings>(
        stream: SettingsService.instance.stream(),
        builder: (context, snap) {
          final title = (snap.data != null && snap.data!.platformTitle.isNotEmpty)
              ? snap.data!.platformTitle
              : 'المنصة التعليمية';
          return Text(
            '$title @ 2025 جميع الحقوق محفوظة - شركة Cotree',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          );
        },
      ),
    );
  }
}
