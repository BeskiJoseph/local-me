import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/backend_service.dart';
import '../services/auth_service.dart';
import '../services/media_upload_service.dart';
import '../config/app_theme.dart';
import '../services/location_service.dart';
import '../utils/proxy_helper.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile? profile;

  const EditProfileScreen({super.key, this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _aboutController = TextEditingController();
  
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = AuthService.currentUser;
    String nameToSet = '';
    
    if (widget.profile != null) {
      nameToSet = widget.profile!.username;
      if (nameToSet.isEmpty || nameToSet == 'User' || nameToSet == 'Unknown') {
        nameToSet = user?.displayName ?? user?.email?.split('@')[0] ?? '';
      }
      _locationController.text = widget.profile!.location ?? LocationService.getLocationString();
      _aboutController.text = widget.profile!.about ?? '';
    }

    // Final safety check: if still empty, use email prefix
    if (nameToSet.isEmpty && user?.email != null) {
      nameToSet = user!.email!.split('@')[0];
    }
    
    _nameController.text = nameToSet;
    if (kDebugMode) debugPrint('👤 EditProfile initialized with name: "$nameToSet"');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final name = _nameController.text.trim();
    final about = _aboutController.text.trim();
    final location = _locationController.text.trim();

    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 3 characters')),
      );
      return;
    }

    if (about.length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('About section cannot exceed 200 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? profileImageUrl = widget.profile?.profileImageUrl;

      // 1. Upload new image if selected
      if (_imageFile != null) {
        final bytes = await _imageFile!.readAsBytes();
        final uploadedUrl = await MediaUploadService.uploadProfileImage(
          userId: user.uid,
          data: bytes,
          fileExtension: _imageFile!.path.split('.').last,
        );
        if (uploadedUrl != null) {
          profileImageUrl = uploadedUrl;
        }
      }

      // 2. Update via backend
      final response = await BackendService.updateProfile({
        'username': _nameController.text.trim(),
        'about': _aboutController.text.trim(),
        'location': _locationController.text.trim(),
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      });

      if (!mounted) return;

      if (response.success) {
        Navigator.pop(context, true); // Return true to trigger refresh
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      } else {
        throw Exception(response.error ?? 'Failed to update profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D6D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isLoading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- TOP PROFILE INFO CARD ---
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[200],
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              image: _imageFile != null 
                                ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                                : (widget.profile?.profileImageUrl != null 
                                    ? DecorationImage(
                                        image: NetworkImage(ProxyHelper.getUrl(widget.profile!.profileImageUrl!)),
                                        fit: BoxFit.cover,
                                      )
                                    : null),
                            ),
                            child: (widget.profile?.profileImageUrl == null && _imageFile == null)
                                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF006D6D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Name Field
                  _buildLabelInput(label: 'Name', controller: _nameController),
                  const SizedBox(height: 16),
                  // Location Field (READ ONLY)
                  _buildLocationInput(controller: _locationController),
                ],
              ),
            ),

            // --- ABOUT SECTION ---
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFBFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: TextField(
                      controller: _aboutController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Add more about yourself...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        contentPadding: EdgeInsets.all(16),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // --- SIGN OUT SECTION ---
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: OutlinedButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text('Sign Out', style: TextStyle(color: Colors.red))
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    // SECURE LOGOUT: Clear custom session first, then Firebase
                    BackendService.clearSession();
                    await AuthService.signOut();
                    
                    if (mounted) {
                      // Navigate back to the initial auth state listener in main.dart
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelInput({required String label, required TextEditingController controller}) {
    final user = AuthService.currentUser;
    final String fallbackHint = user?.displayName ?? user?.email?.split('@')[0] ?? 'Your Name';
    
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 15, color: Color(0xFF64748B)),
              decoration: InputDecoration(
                border: InputBorder.none, 
                isDense: true,
                hintText: fallbackHint,
                hintStyle: const TextStyle(color: Color(0xFFCBD5E0), fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInput({required TextEditingController controller}) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Color(0xFF1E293B), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.text,
              style: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8)), // Greyed out since read-only
            ),
          ),
          const Icon(Icons.lock_outline, color: Color(0xFFCBD5E0), size: 16), // Optional: indicates read-only
        ],
      ),
    );
  }
}
