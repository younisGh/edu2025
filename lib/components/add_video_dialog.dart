import 'package:educational_platform/services/video_service.dart';
import 'package:educational_platform/services/notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:educational_platform/utils/typography.dart';
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
  String _videoType = 'free'; // 'free' or 'paid'
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
                  title: Text(
                    'اختر مقاطع للاستيراد أو لملء الحقول',
                    style: TextStyle(fontSize: sf(context, 16)),
                  ),
                  content: SizedBox(
                    width: sd(context, 520),
                    height: sh(context, 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search box
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'ابحث بعنوان الفيديو...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: sf(context, 12),
                            ),
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                sd(context, 8),
                              ),
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setS(() => filter = v.trim().toLowerCase()),
                        ),
                        SizedBox(height: gapS(context)),
                        // Hint: use "اختيار" to fill, check for bulk import
                        Text(
                          'ملاحظة: استخدم زر "اختيار" لتعبئة الحقول مباشرة، أو حدِّد بعلامات الاختيار للاستيراد الجماعي.',
                          style: TextStyle(
                            fontSize: sf(context, 12),
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        SizedBox(height: gapS(context)),
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
                                      borderRadius: BorderRadius.circular(
                                        sd(context, 6),
                                      ),
                                      child: SizedBox(
                                        width: sd(context, 56),
                                        height: sh(context, 32),
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
                                                      child: Icon(
                                                        Icons
                                                            .ondemand_video_rounded,
                                                        size: sd(context, 18),
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                              )
                                            : Container(
                                                color: const Color(0xFFE5E7EB),
                                                child: Icon(
                                                  Icons.ondemand_video_rounded,
                                                  size: sd(context, 18),
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
                                  style: TextStyle(fontSize: sf(context, 14)),
                                ),
                                subtitle: Text(
                                  v['videoUrl'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: sf(context, 12),
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: Wrap(
                                  spacing: sd(context, 8),
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
                                      child: Text(
                                        'اختيار',
                                        style: TextStyle(
                                          fontSize: sf(context, 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: gapS(context)),
                        Wrap(
                          spacing: sd(context, 8),
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(<int>[]),
                              child: Text(
                                'إلغاء',
                                style: TextStyle(fontSize: sf(context, 14)),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: sel.isEmpty
                                  ? null
                                  : () => Navigator.of(ctx).pop(sel.toList()),
                              icon: const Icon(Icons.download_rounded),
                              label: Text(
                                'استيراد المحدد',
                                style: TextStyle(fontSize: sf(context, 14)),
                              ),
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

  Widget _buildModeSwitcher(Color textPrimary, Color textSecondary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(sd(context, 8)),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isUploadMode = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: sp(context, 10)),
                decoration: BoxDecoration(
                  color: _isUploadMode ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(sd(context, 8)),
                ),
                child: Center(
                  child: Text(
                    'رابط يوتيوب',
                    style: TextStyle(
                      color: _isUploadMode ? textSecondary : textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: sf(context, 14),
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
                padding: EdgeInsets.symmetric(vertical: sp(context, 10)),
                decoration: BoxDecoration(
                  color: _isUploadMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(sd(context, 8)),
                ),
                child: Center(
                  child: Text(
                    'رفع ملف فيديو',
                    style: TextStyle(
                      color: _isUploadMode ? textPrimary : textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: sf(context, 14),
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

  Widget _buildCategoryDropdown(Color textPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الفئة (اختياري)',
          style: TextStyle(
            fontSize: sf(context, 14),
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        SizedBox(height: gapS(context)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('categories')
              .orderBy('name')
              .snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final dropdownItems = <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  'بدون فئة',
                  style: TextStyle(fontSize: sf(context, 14)),
                ),
              ),
              ...docs.map((doc) {
                final data = doc.data();
                final name = (data['name'] ?? '').toString();
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(
                    name.isEmpty ? doc.id : name,
                    style: TextStyle(fontSize: sf(context, 14)),
                  ),
                );
              }),
            ];

            final currentValue = (_selectedCategoryId?.isNotEmpty ?? false)
                ? _selectedCategoryId
                : '';

            return DropdownButtonFormField<String>(
              initialValue: currentValue,
              items: dropdownItems,
              style: TextStyle(fontSize: sf(context, 14)),
              onChanged: (val) {
                setState(() {
                  if (val == null || val.isEmpty) {
                    _selectedCategoryId = null;
                    _selectedCategoryName = null;
                  } else {
                    _selectedCategoryId = val;
                    final doc = docs.firstWhere(
                      (d) => d.id == val,
                      orElse: () => docs.first,
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
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: sf(context, 12),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(sd(context, 8)),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(sd(context, 8)),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(sd(context, 8)),
                  borderSide: const BorderSide(color: Color(0xFFEA2A33)),
                ),
              ),
            );
          },
        ),
      ],
    );
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

  Widget _buildVideoTypeDropdown(Color textPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع الفيديو',
          style: TextStyle(
            fontSize: sf(context, 14),
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        SizedBox(height: gapS(context)),
        DropdownButtonFormField<String>(
          initialValue: _videoType,
          items: const [
            DropdownMenuItem(
              value: 'free',
              child: Text('مجاني'),
            ),
            DropdownMenuItem(
              value: 'paid',
              child: Text('مدفوع'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _videoType = value;
              });
            }
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
              borderSide: const BorderSide(color: Color(0xFFEA2A33)),
            ),
          ),
        ),
      ],
    );
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
          borderRadius: BorderRadius.circular(sd(context, 12)),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxWidth: sd(context, 500)),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(sp(context, 24)),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, textPrimary, textSecondary),
                    SizedBox(height: gapL(context)),
                    _buildModeSwitcher(textPrimary, textSecondary),
                    SizedBox(height: gapM(context)),
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
                                    fontSize: sf(context, 12),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: sd(context, 8)),
                              TextButton.icon(
                                onPressed: (channelId.isEmpty || _isImporting)
                                    ? null
                                    : _openImportPicker,
                                icon: _isImporting
                                    ? SizedBox(
                                        width: sd(context, 14),
                                        height: sh(context, 14),
                                        child: CircularProgressIndicator(
                                          strokeWidth: sd(context, 2),
                                        ),
                                      )
                                    : Icon(
                                        Icons.download_rounded,
                                        size: sd(context, 18),
                                      ),
                                label: Text(
                                  'استيراد',
                                  style: TextStyle(fontSize: sf(context, 14)),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: gapS(context)),
                      _buildTextField(
                        controller: _videoUrlController,
                        label: 'رابط الفيديو',
                        hint: "الصق رابط الفيديو هنا",
                        hintTextStyle: TextStyle(
                          color: const Color.fromARGB(255, 115, 114, 114),
                          fontSize: sf(context, 12),
                        ),
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
                    SizedBox(height: gapL(context)),
                    _buildCategoryDropdown(textPrimary),
                    SizedBox(height: gapL(context)),
                    _buildVideoTypeDropdown(textPrimary),
                    SizedBox(height: gapL(context)),
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
                    SizedBox(height: gapL(context)),
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
                    SizedBox(height: gapL(context)),
                    _buildPdfUpload(textPrimary, textSecondary, primaryColor),
                    SizedBox(height: gapL(context)),
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

  // (Removed a corrupted duplicate of _buildHeader here)

  Widget _buildVideoUpload(Color textPrimary, Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ملف الفيديو',
          style: TextStyle(
            fontSize: sf(context, 14),
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        SizedBox(height: gapS(context)),
        GestureDetector(
          onTap: _pickVideoFile,
          child: Container(
            height: sd(context, 132),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey[300]!,
                style: BorderStyle.solid,
                width: sd(context, 2),
              ),
              borderRadius: BorderRadius.circular(sd(context, 8)),
            ),
            child: Center(
              child: _videoFile == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.video_file_rounded,
                          size: sd(context, 32),
                          color: textSecondary,
                        ),
                        SizedBox(height: gapS(context)),
                        Text(
                          'قم باختيار ملف فيديو أو اسحبه هنا',
                          style: TextStyle(
                            fontSize: sf(context, 14),
                            color: textSecondary,
                          ),
                        ),
                        SizedBox(height: sp(context, 4)),
                        Text(
                          'MP4, MOV, MKV, AVI, WEBM (حتى 200 ميجا تقريباً)',
                          style: TextStyle(
                            fontSize: sf(context, 12),
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: sd(context, 40),
                          color: Colors.green,
                        ),
                        SizedBox(height: gapS(context)),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: sp(context, 8),
                          ),
                          child: Text(
                            _videoFile!.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: sf(context, 14),
                              color: textPrimary,
                            ),
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
            Expanded(
              child: Text(
                'إضافة فيديو',
                style: TextStyle(
                  fontSize: sf(context, 22),
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: sd(context, 20)),
              color: textSecondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        SizedBox(height: sp(context, 4)),
        Text(
          ' املء التفاصيل أدناه لإضافة فيديو',
          style: TextStyle(color: textSecondary, fontSize: sf(context, 14)),
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
    TextStyle? hintTextStyle,
    TextStyle? textStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: sf(context, 14),
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        SizedBox(height: gapS(context)),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          style: textStyle,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                hintTextStyle ??
                TextStyle(color: Colors.grey[400], fontSize: sf(context, 12)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: sd(context, 16),
              vertical: sd(context, 12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
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
            fontSize: sf(context, 14),
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
        SizedBox(height: gapS(context)),
        GestureDetector(
          onTap: _pickPdfFile,
          child: Container(
            height: sd(context, 132),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey[300]!,
                style: BorderStyle.solid,
                width: sd(context, 2),
              ),
              borderRadius: BorderRadius.circular(sd(context, 8)),
            ),
            child: Center(
              child: _pdfFile == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.picture_as_pdf,
                          size: sd(context, 32),
                          color: textSecondary,
                        ),
                        SizedBox(height: gapS(context)),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: sf(context, 14),
                              color: textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: 'قم بتحميل ملف',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                              const TextSpan(text: ' أو قم بسحبه وإفلاته هنا'),
                            ],
                          ),
                        ),
                        SizedBox(height: sp(context, 4)),
                        Text(
                          'PDF فقط (حتى 20 ميجا تقريباً)',
                          style: TextStyle(
                            fontSize: sf(context, 12),
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: sd(context, 40),
                          color: Colors.green,
                        ),
                        SizedBox(height: gapS(context)),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: sp(context, 8),
                          ),
                          child: Text(
                            _pdfFile!.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: sf(context, 14),
                              color: textPrimary,
                            ),
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
            padding: EdgeInsets.symmetric(
              horizontal: sd(context, 24),
              vertical: sd(context, 12),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
            ),
          ),
          child: Text(
            'إلغاء',
            style: TextStyle(color: Colors.black87, fontSize: sf(context, 14)),
          ),
        ),
        SizedBox(width: sd(context, 12)),
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
                        videoType: _videoType, // Pass the video type
                      );

                      if (!ctx.mounted) return;

                      // Ask to send notification to users
                      final send = await showDialog<bool>(
                        context: ctx,
                        builder: (context) => AlertDialog(
                          title: Text(
                            'إرسال إشعار؟',
                            style: TextStyle(fontSize: sf(context, 16)),
                          ),
                          content: Text(
                            'تمت إضافة الفيديو بنجاح. هل تريد إرسال إشعار للمستخدمين؟',
                            style: TextStyle(fontSize: sf(context, 14)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(
                                'لا',
                                style: TextStyle(fontSize: sf(context, 14)),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(
                                'نعم',
                                style: TextStyle(fontSize: sf(context, 14)),
                              ),
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
            padding: EdgeInsets.symmetric(
              horizontal: sd(context, 24),
              vertical: sd(context, 12),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(sd(context, 8)),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: sd(context, 20),
                  width: sd(context, 20),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: sd(context, 3),
                  ),
                )
              : Text('إضافة', style: TextStyle(fontSize: sf(context, 14))),
        ),
      ],
    );
  }
}
