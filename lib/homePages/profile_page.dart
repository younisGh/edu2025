import 'package:flutter/material.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:educational_platform/components/arrow_scroll.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

// Define custom colors for a modern look
const Color primaryColor = Color(0xFF6D28D9);
const Color secondaryColor = Color(0xFFEDE9FE);
const Color textColor = Color(0xFF1F2937);
const Color subTextColor = Color(0xFF6B7280);
const Color backgroundColor = Color(0xFFF8FAFC);
const Color cardBackgroundColor = Colors.white;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _user;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  bool _isNameEditing = false;
  bool _isPhoneEditing = false;
  bool _isEmailEditing = false;
  bool _isAddressEditing = false;
  bool _isLoading = true;
  bool _isUploading = false;
  Future<String?>? _photoUrlFuture;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _user = user;
      });
      try {
        final userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .get();
        if (userData.exists) {
          final data = userData.data() as Map<String, dynamic>;
          _nameController = TextEditingController(
            text: data['name'] ?? 'اسم المستخدم',
          );
          _phoneController = TextEditingController(
            text: data['phone'] ?? 'رقم الهاتف',
          );
          _emailController = TextEditingController(
            text: data['email'] ?? 'البريد الإلكتروني',
          );
          _addressController = TextEditingController(
            text: data['address'] ?? 'العنوان',
          );
          final pictureUrl = data['pictureUrl'] as String?;
          if (pictureUrl != null && pictureUrl.isNotEmpty) {
            // Assign the future to be resolved by the FutureBuilder
            _photoUrlFuture = _getDownloadUrl(pictureUrl);
          }
        }
      } catch (e) {
        // Handle errors
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String?> _getDownloadUrl(String pictureUrl) async {
    try {
      if (pictureUrl.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(pictureUrl);
        return await ref.getDownloadURL();
      } else {
        return pictureUrl;
      }
    } catch (e) {
      debugPrint('Failed to get download URL: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
            : Stack(
                children: [
                  _buildBackground(context),
                  SafeArea(
                    child: ArrowScroll(
                      scrollController: _scrollController,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            children: [
                              const SizedBox(height: 80), // Space for back button
                              _buildProfileHeader(),
                              const SizedBox(height: 32),
                              _buildPersonalInfoSection(),
                              const SizedBox(height: 32),
                              _buildActionButtons(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildCustomBackButton(context),
                ],
              ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.25, // Adjusted height
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, Color(0xFF8B5CF6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(50),
          bottomRight: Radius.circular(50),
        ),
      ),
    );
  }

  Widget _buildCustomBackButton(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Align(
          alignment: Alignment.topRight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: sd(context, 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    if (_user == null) return;

    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final ctx = context;
      final ref = FirebaseStorage.instance.ref(
        'profile_pictures/${_user!.uid}',
      );

      // Upload file using bytes, which works for both web and mobile
      await ref.putData(
        await pickedFile.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Get download URL and update Firestore
      final downloadUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({'pictureUrl': downloadUrl});

      // Refresh the UI
      setState(() {
        _photoUrlFuture = Future.value(downloadUrl);
      });

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الصورة بنجاح!', textAlign: TextAlign.center),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء رفع الصورة: $e',
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Widget _buildProfileHeader() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              FutureBuilder<String?>(
                future: _photoUrlFuture,
                builder: (context, snapshot) {
                  ImageProvider<Object> imageProvider;
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData &&
                      snapshot.data != null) {
                    imageProvider = NetworkImage(snapshot.data!);
                  } else {
                    imageProvider = const NetworkImage(
                      'https://via.placeholder.com/150',
                    );
                  }

                  return CircleAvatar(
                    radius: 70,
                    backgroundColor: secondaryColor,
                    backgroundImage: imageProvider,
                    child: (snapshot.connectionState == ConnectionState.waiting)
                        ? const CircularProgressIndicator(color: primaryColor)
                        : null,
                  );
                },
              ),
              if (_isUploading)
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Padding(
                padding: EdgeInsets.all(sd(context, 8.0)),
                child: Icon(Icons.camera_alt, color: Colors.white, size: sd(context, 20)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalInfoSection() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المعلومات الشخصية',
            style: TextStyle(
              fontSize: sf(context, 20),
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.person_outline,
            label: 'الاسم',
            controller: _nameController,
            isEditing: _isNameEditing,
            onToggle: () => setState(() => _isNameEditing = !_isNameEditing),
          ),
          const SizedBox(height: 24),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'رقم الهاتف',
            controller: _phoneController,
            isEditing: _isPhoneEditing,
            onToggle: () => setState(() => _isPhoneEditing = !_isPhoneEditing),
          ),
          const SizedBox(height: 24),
          _buildInfoRow(
            icon: Icons.email_outlined,
            label: 'البريد الإلكتروني',
            controller: _emailController,
            isEditing: _isEmailEditing,
            onToggle: () => setState(() => _isEmailEditing = !_isEmailEditing),
          ),
          const SizedBox(height: 24),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'العنوان',
            controller: _addressController,
            isEditing: _isAddressEditing,
            onToggle: () =>
                setState(() => _isAddressEditing = !_isAddressEditing),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required bool isEditing,
    required VoidCallback onToggle,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: secondaryColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: primaryColor, size: sd(context, 24)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: sf(context, 14), color: subTextColor),
              ),
              const SizedBox(height: 4),
              isEditing
                  ? TextField(
                      controller: controller,
                      style: TextStyle(
                        fontSize: sf(context, 16),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      autofocus: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    )
                  : Text(
                      controller.text,
                      style: TextStyle(
                        fontSize: sf(context, 16),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            isEditing ? Icons.check_circle : Icons.edit_outlined,
            color: isEditing ? primaryColor : subTextColor,
            size: sd(context, 20),
          ),
          onPressed: onToggle,
          splashRadius: sd(context, 20),
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Future<void> _saveAllChanges() async {
    if (_user == null) return;

    setState(() {
      _isNameEditing = false;
      _isPhoneEditing = false;
      _isEmailEditing = false;
      _isAddressEditing = false;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
        'name': _nameController.text,
        'phone': _phoneController.text,
        'email': _emailController
            .text, // Note: Changing email in Auth requires a different process
        'address': _addressController.text,
      });
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ التغييرات بنجاح!', textAlign: TextAlign.center),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء حفظ التغييرات: $e',
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        _buildActionButton(
          icon: Icons.save_alt_outlined,
          text: 'حفظ كل التغييرات',
          onTap: _saveAllChanges,
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.lock_outline,
          text: 'تغيير كلمة المرور',
          onTap: () {},
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.logout,
          text: 'تسجيل الخروج',
          isLogout: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isLogout ? Colors.redAccent : primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: sf(context, 16),
                      fontWeight: FontWeight.w600,
                      color: isLogout ? Colors.redAccent : textColor,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: subTextColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
