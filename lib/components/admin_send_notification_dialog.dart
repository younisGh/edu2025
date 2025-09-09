import 'package:flutter/material.dart';
import 'package:educational_platform/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminSendNotificationDialog extends StatefulWidget {
  const AdminSendNotificationDialog({super.key});

  @override
  State<AdminSendNotificationDialog> createState() =>
      _AdminSendNotificationDialogState();
}

class _AdminSendNotificationDialogState
    extends State<AdminSendNotificationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _broadcast = true;
  bool _loading = false;
  String? _error;

  // For single user selection
  List<_UserOption> _userOptions = const [];
  String? _selectedUid;
  bool _usersLoading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Preload users for the dropdown (excluding current user)
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _usersLoading = true);
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('name', descending: false)
          .get();
      final list =
          snap.docs.where((d) => d.id != currentUid).map((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().trim();
            final phone = (data['phone'] ?? '').toString().trim();
            final display = name.isNotEmpty
                ? name
                : (phone.isNotEmpty ? phone : d.id);
            return _UserOption(uid: d.id, display: display);
          }).toList()..sort(
            (a, b) =>
                a.display.toLowerCase().compareTo(b.display.toLowerCase()),
          );
      setState(() {
        _userOptions = list;
        // Keep previous selection if still valid
        if (_selectedUid != null &&
            !_userOptions.any((u) => u.uid == _selectedUid)) {
          _selectedUid = null;
        }
      });
    } catch (e) {
      setState(() => _error = 'تعذر تحميل المستخدمين: $e');
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await NotificationService.instance.sendAdminNotification(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        broadcast: _broadcast,
        targetUid: _broadcast ? null : _selectedUid,
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل العنوان' : null,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(labelText: 'نص الإشعار'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل النص' : null,
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'اختر مستخدمًا لإرسال إشعار فردي',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_usersLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUid,
                      items: _userOptions
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u.uid,
                              child: Text(
                                u.display,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedUid = v),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'اختر مستخدمًا' : null,
                      decoration: const InputDecoration(
                        labelText: 'المستخدم المستهدف',
                        hintText: 'اختر مستخدمًا',
                      ),
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
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('إرسال'),
          ),
        ],
      ),
    );
  }
}

class _UserOption {
  final String uid;
  final String display;
  const _UserOption({required this.uid, required this.display});
}
