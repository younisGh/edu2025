import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

class ViewingRequestsPage extends StatefulWidget {
  const ViewingRequestsPage({super.key});

  @override
  State<ViewingRequestsPage> createState() => _ViewingRequestsPageState();
}

class _ViewingRequestsPageState extends State<ViewingRequestsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _revokeApproval(String requestId, String userId, String videoId) async {
    try {
      // Validate against the source request to ensure correctness and current state
      final reqSnap = await _firestore.collection('viewing_requests').doc(requestId).get();
      if (!reqSnap.exists) throw Exception('الطلب غير موجود');
      final rd = reqSnap.data() as Map<String, dynamic>;
      final reqUserId = (rd['userId'] ?? userId).toString();
      final reqVideoId = (rd['videoId'] ?? videoId).toString();
      final status = (rd['status'] ?? 'pending').toString();

      // Only allow revoke if currently approved
      if (status != 'approved') throw Exception('لا يمكن إلغاء الموافقة لطلب غير مُعتمد');

      WriteBatch batch = _firestore.batch();
      final requestRef = _firestore.collection('viewing_requests').doc(requestId);
      batch.update(requestRef, {'status': 'pending'});

      final userRef = _firestore.collection('users').doc(reqUserId);
      // Use set with merge to avoid errors if user doc doesn't exist
      batch.set(userRef, {
        'accessibleVideos': FieldValue.arrayRemove([reqVideoId])
      }, SetOptions(merge: true));

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الموافقة بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إلغاء الموافقة: $e')),
      );
    }
  }

  Future<void> _approveRequest(String requestId, String userId, String videoId) async {
    try {
      // Read request to validate and get authoritative user/video
      final reqSnap = await _firestore.collection('viewing_requests').doc(requestId).get();
      if (!reqSnap.exists) throw Exception('الطلب غير موجود');
      final rd = reqSnap.data() as Map<String, dynamic>;
      final reqUserId = (rd['userId'] ?? userId).toString();
      final reqVideoId = (rd['videoId'] ?? videoId).toString();
      final status = (rd['status'] ?? 'pending').toString();

      if (status == 'approved') {
        // Already approved, nothing to do
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا الطلب مُعتمد بالفعل')),
          );
        }
        return;
      }

      WriteBatch batch = _firestore.batch();
      final requestRef = _firestore.collection('viewing_requests').doc(requestId);
      batch.update(requestRef, {'status': 'approved'});

      final userRef = _firestore.collection('users').doc(reqUserId);
      // Use set with merge to avoid 400 if user doc doesn't exist
      batch.set(userRef, {
        'accessibleVideos': FieldValue.arrayUnion([reqVideoId])
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت الموافقة على الطلب بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات المشاهدة'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('viewing_requests')
            .orderBy('requestDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ في تحميل البيانات.'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد طلبات مشاهدة حالياً.'));
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              if (isWide) {
                // Desktop/Tablet wide: full-width DataTable view
                return _buildDataTableView(docs, constraints.maxWidth);
              }
              // Mobile: Card list view (also good for medium widths)
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final d = docs[index].data() as Map<String, dynamic>;
                  final requestId = docs[index].id;
                  final status = (d['status'] ?? 'pending').toString();
                  final isApproved = status == 'approved';
                  final ts = d['requestDate'];
                  final date = ts is Timestamp ? ts.toDate() : DateTime.now();
                  final formattedDate = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(date);

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (d['videoTitle'] ?? 'فيديو غير معروف').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _metaChip(Icons.person_outline, (d['userName'] ?? 'غير معروف').toString()),
                                        _metaChip(Icons.schedule, formattedDate),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _statusChip(isApproved ? 'تمت الموافقة' : 'في الانتظار', isApproved),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 36,
                                    child: isApproved
                                        ? OutlinedButton.icon(
                                            onPressed: () => _revokeApproval(
                                              requestId,
                                              (d['userId'] ?? '').toString(),
                                              (d['videoId'] ?? '').toString(),
                                            ),
                                            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                                            label: const Text('إلغاء الموافقة', style: TextStyle(color: Colors.red)),
                                          )
                                        : ElevatedButton.icon(
                                            onPressed: () => _approveRequest(
                                              requestId,
                                              (d['userId'] ?? '').toString(),
                                              (d['videoId'] ?? '').toString(),
                                            ),
                                            icon: const Icon(Icons.check_circle_outline, size: 18),
                                            label: const Text('موافقة'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // Modern status chip
  Widget _statusChip(String label, bool approved) {
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: approved ? Colors.green : Colors.orange,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
    );
  }

  // DataTable view for wide screens
  Widget _buildDataTableView(List<QueryDocumentSnapshot> docs, double width) {
    final rows = docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final requestId = doc.id;
      final status = (d['status'] ?? 'pending').toString();
      final isApproved = status == 'approved';
      final ts = d['requestDate'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.now();
      final formattedDate = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(date);
      return DataRow(cells: [
        DataCell(Text((d['videoTitle'] ?? '—').toString())),
        DataCell(Text((d['userName'] ?? '—').toString())),
        DataCell(Text(formattedDate)),
        DataCell(_statusChip(isApproved ? 'تمت الموافقة' : 'في الانتظار', isApproved)),
        DataCell(Row(
          children: [
            if (!isApproved)
              ElevatedButton.icon(
                onPressed: () => _approveRequest(
                  requestId,
                  (d['userId'] ?? '').toString(),
                  (d['videoId'] ?? '').toString(),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('موافقة'),
              ),
            if (isApproved)
              OutlinedButton.icon(
                onPressed: () => _revokeApproval(
                  requestId,
                  (d['userId'] ?? '').toString(),
                  (d['videoId'] ?? '').toString(),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                label: const Text('إلغاء الموافقة', style: TextStyle(color: Colors.red)),
              ),
          ],
        )),
      ]);
    }).toList();

    // Full-width table; keep a minimum width to avoid cramped columns.
    final tableMinWidth = 900.0;
    final tableWidth = width < tableMinWidth ? tableMinWidth : width;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('الفيديو')),
            DataColumn(label: Text('المستخدم')),
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('إجراء')),
          ],
          rows: rows,
          dividerThickness: 0.6,
          dataRowMaxHeight: 60,
        ),
      ),
    );
  }

  // Small info chip to avoid Row overflow inside tight Wraps
  Widget _metaChip(IconData icon, String text) {
    return Chip(
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      avatar: Icon(icon, size: 16, color: const Color(0xFF475569)),
      label: Text(
        text,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
      backgroundColor: const Color(0xFFF1F5F9),
      side: const BorderSide(color: Color(0xFFE5E7EB)),
    );
  }
}
