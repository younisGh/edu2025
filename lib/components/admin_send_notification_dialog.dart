import 'package:flutter/material.dart';
import 'package:educational_platform/services/notification_service.dart';

class AdminSendNotificationDialog extends StatefulWidget {
  const AdminSendNotificationDialog({super.key});

  @override
  State<AdminSendNotificationDialog> createState() => _AdminSendNotificationDialogState();
}

class _AdminSendNotificationDialogState extends State<AdminSendNotificationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  bool _broadcast = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await NotificationService.instance.sendAdminNotification(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        broadcast: _broadcast,
        targetUid: _broadcast ? null : _targetCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'فشل إرسال الإشعار: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إرسال إشعار للمستخدمين'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل العنوان' : null,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(labelText: 'نص الإشعار'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل النص' : null,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('إرسال للجميع (بث)؟'),
                  value: _broadcast,
                  onChanged: (val) => setState(() => _broadcast = val),
                ),
                if (!_broadcast) ...[
                  TextFormField(
                    controller: _targetCtrl,
                    decoration: const InputDecoration(labelText: 'معرّف المستخدم المستهدف (UID)'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل UID' : null,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('إرسال'),
          )
        ],
      ),
    );
  }
}
