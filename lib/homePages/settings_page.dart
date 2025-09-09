import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _titleCtrl = TextEditingController();
  final _channelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _savingGeneral = false;

  DocumentReference<Map<String, dynamic>> get _generalRef =>
      FirebaseFirestore.instance.collection('app_config').doc('general');

  CollectionReference<Map<String, dynamic>> get _categoriesCol =>
      FirebaseFirestore.instance.collection('categories');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _channelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveGeneral() async {
    setState(() => _savingGeneral = true);
    try {
      await _generalRef.set({
        'platformTitle': _titleCtrl.text.trim(),
        'channelId': _channelCtrl.text.trim(),
        'platformDescription': _descCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات المنصة')));
      }
    } finally {
      if (mounted) setState(() => _savingGeneral = false);
    }
  }

  Future<void> _showCategoryDialog({
    String? id,
    String initialName = '',
  }) async {
    final ctrl = TextEditingController(text: initialName);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(id == null ? 'إضافة صنف' : 'تعديل الصنف'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'اسم الصنف',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                if (id == null) {
                  await _categoriesCol.add({
                    'name': name,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await _categoriesCol.doc(id).update({
                    'name': name,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                }
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteCategory(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف'),
        content: const Text(
          'هل أنت متأكد من حذف هذا الصنف؟ قد يؤثر على تصنيف الفيديوهات.',
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
    );
    if (ok == true) {
      await _categoriesCol.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCategoryDialog(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة صنف'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _generalRef.snapshots(),
                    builder: (context, snap) {
                      final data = (snap.data?.data()) ?? {};
                      _titleCtrl.value = TextEditingValue(
                        text: (data['platformTitle'] ?? '').toString(),
                      );
                      _channelCtrl.value = TextEditingValue(
                        text: (data['channelId'] ?? '').toString(),
                      );
                      _descCtrl.value = TextEditingValue(
                        text: (data['platformDescription'] ?? '').toString(),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إعدادات عامة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'عنوان المنصة',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'وصف المنصة',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _channelCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Channel ID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _savingGeneral ? null : _saveGeneral,
                              icon: const Icon(Icons.save),
                              label: Text(
                                _savingGeneral ? 'جارٍ الحفظ...' : 'حفظ',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الأصناف',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _categoriesCol.orderBy('name').snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final docs = snap.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('لا توجد أصناف حتى الآن.'),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final doc = docs[i];
                              final data = doc.data();
                              return ListTile(
                                leading: const Icon(Icons.label_outline),
                                title: Text(data['name'] ?? ''),
                                subtitle: Text(
                                  doc.id,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'edit') {
                                      await _showCategoryDialog(
                                        id: doc.id,
                                        initialName: (data['name'] ?? '')
                                            .toString(),
                                      );
                                    } else if (v == 'delete') {
                                      await _confirmDeleteCategory(doc.id);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
