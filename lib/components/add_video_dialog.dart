import 'package:educational_platform/services/video_service.dart';
import 'package:educational_platform/services/notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:educational_platform/services/settings_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AddVideoDialog extends StatefulWidget {
  const AddVideoDialog({super.key});

  @override
  State<AddVideoDialog> createState() => _AddVideoDialogState();
}

class _AddVideoDialogState extends State<AddVideoDialog> {
  final _formKey = GlobalKey<FormState>();
  PlatformFile? _pdfFile;
  PlatformFile? _videoFile; // New: selected video file
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _videoUrlController = TextEditingController(); // For YouTube URL
  final _videoService = VideoService();
  bool _isLoading = false;
  bool _isUploadMode = false; // false: link mode (YouTube), true: upload mode
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  bool _isImporting = false;

  Future<void> _openImportPicker() async {
    final settings = await SettingsService.instance.getOnce();
    final channelId = (settings.channelId).trim();
    if (channelId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم تعيين معرف القناة بعد')),
      );
      return;
    }
    setState(() => _isImporting = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'listYouTubeChannelVideos',
      );
      final res = await callable.call({'channelId': channelId});
      if (!mounted) return;
      final data = (res.data as Map?) ?? {};
      final List items = (data['items'] as List?) ?? [];
      final videos = items
          .map<Map<String, dynamic>>(
            (e) => {
              'videoId': e['videoId']?.toString() ?? '',
              'title': e['title']?.toString() ?? '',
              'description': e['description']?.toString() ?? '',
              'videoUrl': e['videoUrl']?.toString() ?? '',
              'thumbnailUrl': e['thumbnailUrl']?.toString() ?? '',
              'publishedAt': e['publishedAt'],
            },
          )
          .toList();

      // Open selection dialog
      final selected = await showDialog<List<int>>(
        context: context,
        builder: (ctx) {
          final Set<int> sel = {};
          String filter = '';
          return StatefulBuilder(
            builder: (ctx, setS) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: const Text('اختر مقاطع للاستيراد أو لملء الحقول'),
                  content: SizedBox(
                    width: 520,
                    height: 420,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search box
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'ابحث بعنوان الفيديو...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setS(() => filter = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 8),
                        // Hint: use "اختيار" to fill, check for bulk import
                        const Text(
                          'ملاحظة: استخدم زر "اختيار" لتعبئة الحقول مباشرة، أو حدِّد بعلامات الاختيار للاستيراد الجماعي.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: videos.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final v = videos[i];
                              final title = (v['title']?.toString() ?? '');
                              if (filter.isNotEmpty &&
                                  !title.toLowerCase().contains(filter)) {
                                return const SizedBox.shrink();
                              }
                              final checked = sel.contains(i);
                              return ListTile(
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: checked,
                                      onChanged: (_) => setS(() {
                                        if (checked) {
                                          sel.remove(i);
                                        } else {
                                          sel.add(i);
                                        }
                                      }),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        width: 56,
                                        height: 32,
                                        child:
                                            (v['thumbnailUrl']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true)
                                            ? Image.network(
                                                v['thumbnailUrl'],
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    Container(
                                                      color: const Color(
                                                        0xFFE5E7EB,
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .ondemand_video_rounded,
                                                        size: 18,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                              )
                                            : Container(
                                                color: const Color(0xFFE5E7EB),
                                                child: const Icon(
                                                  Icons.ondemand_video_rounded,
                                                  size: 18,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  title.isEmpty == true
                                      ? (v['videoId'] ?? '')
                                      : title,
                                ),
                                subtitle: Text(
                                  v['videoUrl'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (sel.contains(i))
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(<int>[i, -1]),
                                      child: const Text('اختيار'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(<int>[]),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton.icon(
                              onPressed: sel.isEmpty
                                  ? null
                                  : () => Navigator.of(ctx).pop(sel.toList()),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('استيراد المحدد'),
                            ),
                            // Single-fill is now done by tapping the item directly
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (!mounted) return;
      // Handle result
      if (selected == null) return; // canceled
      if (selected.isEmpty) return; // canceled via button

      // If second element is -1 => single fill
      if (selected.length == 2 && selected[1] == -1) {
        final idx = selected.first;
        if (idx >= 0 && idx < videos.length) {
          final v = videos[idx];
          setState(() {
            _titleController.text = (v['title'] ?? '').toString();
            _videoUrlController.text = (v['videoUrl'] ?? '').toString();
            _descriptionController.text = (v['description'] ?? '').toString();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تعبئة الحقول من المقطع المحدد')),
          );
        }
        return;
      }

      // Bulk import selected
      final selIdx = selected
          .where((i) => i >= 0 && i < videos.length)
          .toList();
      if (selIdx.isEmpty) return;
      int ok = 0, fail = 0;
      for (final i in selIdx) {
        final v = videos[i];
        try {
          await _videoService.addVideo(
            name: (v['title'] ?? '').toString(),
            description: (v['description'] ?? '').toString(),
            videoUrl: (v['videoUrl'] ?? '').toString(),
            pdfFile: null,
            videoFile: null,
            categoryId: _selectedCategoryId,
            categoryName: _selectedCategoryName,
          );
          ok++;
        } catch (_) {
          fail++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم استيراد $ok، فشل $fail')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر جلب مقاطع القناة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _pickPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _pdfFile = result.files.first;
      });
    }
  }

  Future<void> _pickVideoFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'mkv', 'avi', 'webm'],
      withData: true,
    );
    if (result != null) {
      setState(() {
        _videoFile = result.files.first;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFEA2A33);
    const textPrimary = Color(0xFF18181B);
    const textSecondary = Color(0xFF71717A);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, textPrimary, textSecondary),
                    const SizedBox(height: 32),
                    _buildModeSwitcher(textPrimary, textSecondary),
                    const SizedBox(height: 16),
                    if (!_isUploadMode) ...[
                      // Channel helper + Import button
                      StreamBuilder<AppSettings>(
                        stream: SettingsService.instance.stream(),
                        builder: (context, snap) {
                          final channelId = (snap.data?.channelId ?? '').trim();
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  channelId.isEmpty
                                      ? 'لم يتم تعيين معرف القناة بعد من صفحة الإعدادات'
                                      : 'معرف القناة المحفوظ: $channelId',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: (channelId.isEmpty || _isImporting)
                                    ? null
                                    : _openImportPicker,
                                icon: _isImporting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_rounded,
                                        size: 18,
                                      ),
                                label: const Text('استيراد'),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _videoUrlController,
                        label: 'رابط الفيديو',
                        hint: 'الصق رابط الفيديو من يوتيوب هنا...',
                        textPrimary: textPrimary,
                        validator: (value) {
                          if (_isUploadMode) {
                            return null; // skip when upload mode
                          }
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال رابط الفيديو';
                          }
                          if (!Uri.parse(value).isAbsolute) {
                            return 'الرجاء إدخال رابط صحيح';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_isUploadMode) ...[
                      _buildVideoUpload(textPrimary, textSecondary),
                    ],
                    const SizedBox(height: 24),
                    _buildCategoryDropdown(textPrimary),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _titleController,
                      label: 'عنوان الفيديو',
                      hint: 'مثال: شرح أساسيات تصميم الواجهات',
                      textPrimary: textPrimary,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الرجاء إدخال عنوان الفيديو';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _descriptionController,
                      label: 'تفاصيل الفيديو',
                      hint: 'أدخل وصفًا تفصيليًا لمحتوى الفيديو...',
                      textPrimary: textPrimary,
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الرجاء إدخال تفاصيل الفيديو';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildPdfUpload(textPrimary, textSecondary, primaryColor),
                    const SizedBox(height: 32),
                    _buildActionButtons(context, primaryColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(Color textPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الفئة (اختياري)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('categories')
              .orderBy('name')
              .snapshots(),
          builder: (context, snapshot) {
            final items = snapshot.data?.docs ?? [];
            final dropdownItems = <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: '',
                child: Text('بدون فئة'),
              ),
              ...items.map((doc) {
                final data = doc.data();
                final name = (data['name'] ?? '').toString();
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(name.isEmpty ? doc.id : name),
                );
              }),
            ];

            // Ensure selected id is valid
            final currentValue = (_selectedCategoryId?.isNotEmpty ?? false)
                ? _selectedCategoryId
                : '';

            return DropdownButtonFormField<String>(
              initialValue: currentValue,
              items: dropdownItems,
              onChanged: (val) {
                setState(() {
                  if (val == null || val.isEmpty) {
                    _selectedCategoryId = null;
                    _selectedCategoryName = null;
                  } else {
                    _selectedCategoryId = val;
                    final doc = items.firstWhere(
                      (d) => d.id == val,
                      orElse: () => items.first,
                    );
                    final data = doc.data();
                    _selectedCategoryName = (data['name'] ?? '').toString();
                  }
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'اختر فئة للفيديو (اختياري)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFEA2A33)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildModeSwitcher(Color textPrimary, Color textSecondary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isUploadMode = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isUploadMode ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'رابط يوتيوب',
                    style: TextStyle(
                      color: _isUploadMode ? textSecondary : textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isUploadMode = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isUploadMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'رفع ملف فيديو',
                    style: TextStyle(
                      color: _isUploadMode ? textPrimary : textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoUpload(Color textPrimary, Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ملف الفيديو',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickVideoFile,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey[300]!,
                style: BorderStyle.solid,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: _videoFile == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.video_file_rounded,
                          size: 32,
                          color: textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قم باختيار ملف فيديو أو اسحبه هنا',
                          style: TextStyle(fontSize: 14, color: textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'MP4, MOV, MKV, AVI, WEBM (حتى 200 ميجا تقريباً)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 40,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            _videoFile!.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: textPrimary),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'إضافة فيديو جديد',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: textSecondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'قم بملء التفاصيل أدناه لإضافة فيديو جديد إلى المنصة.',
          style: TextStyle(color: textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required Color textPrimary,
    required TextEditingController controller,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEA2A33)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPdfUpload(
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ملف PDF ذو صلة',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickPdfFile,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey[300]!,
                style: BorderStyle.solid,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: _pdfFile == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.picture_as_pdf,
                          size: 32,
                          color: textSecondary,
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: textSecondary,
                              fontFamily: 'Noto Kufi Arabic',
                            ),
                            children: [
                              TextSpan(
                                text: 'قم بتحميل ملف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              const TextSpan(text: ' أو قم بسحبه وإفلاته هنا'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PDF (بحد أقصى 10 ميجا)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, size: 40, color: Colors.green),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            _pdfFile!.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: textPrimary),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            backgroundColor: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('إلغاء', style: TextStyle(color: Colors.black87)),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _isLoading
              ? null
              : () async {
                  if (_formKey.currentState!.validate()) {
                    // Additional validation for upload mode
                    if (_isUploadMode && _videoFile == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('الرجاء اختيار ملف الفيديو'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      _isLoading = true;
                    });
                    // Capture context to avoid using State.context across async gaps
                    final ctx = context;

                    try {
                      await _videoService.addVideo(
                        name: _titleController.text, // Changed from title
                        description: _descriptionController.text,
                        videoUrl: _isUploadMode ? '' : _videoUrlController.text,
                        pdfFile: _pdfFile,
                        videoFile: _isUploadMode ? _videoFile : null,
                        categoryId: _selectedCategoryId,
                        categoryName: _selectedCategoryName,
                      );

                      if (!ctx.mounted) return;

                      // Ask to send notification to users
                      final send = await showDialog<bool>(
                        context: ctx,
                        builder: (context) => AlertDialog(
                          title: const Text('إرسال إشعار؟'),
                          content: const Text(
                            'تمت إضافة الفيديو بنجاح. هل تريد إرسال إشعار للمستخدمين؟',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('لا'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('نعم'),
                            ),
                          ],
                        ),
                      );

                      if (send == true) {
                        try {
                          // Lazy import to avoid top-level dependency in this file
                          // ignore: avoid_dynamic_calls
                          await NotificationService.instance
                              .sendAdminNotification(
                                title: 'فيديو جديد: ${_titleController.text}',
                                body: _descriptionController.text.trim().isEmpty
                                    ? 'تمت إضافة فيديو جديد'
                                    : _descriptionController.text.trim(),
                                broadcast: true,
                              );
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('تم إرسال الإشعار')),
                            );
                          }
                        } catch (_) {
                          // Ignore sending error but inform admin
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر إرسال الإشعار'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      }

                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('تمت إضافة الفيديو بنجاح!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.of(ctx).pop();
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('حدث خطأ: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      if (ctx.mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : const Text('إضافة'),
        ),
      ],
    );
  }
}
