import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../widgets/primary_button.dart';
import '../../models/signup_data.dart';
import '../../services/auth_service.dart';
import '../../utils/safe_error.dart';
import '../../services/media_upload_service.dart';
import '../../services/user_service.dart';
import '../../core/session/user_session.dart';
import '../home_screen.dart';
import '../../services/backend_service.dart';

class SignupProfileScreen extends StatefulWidget {
  final SignupData data;
  const SignupProfileScreen({super.key, required this.data});

  @override
  State<SignupProfileScreen> createState() => _SignupProfileScreenState();
}

class _SignupProfileScreenState extends State<SignupProfileScreen> {
  Uint8List? _profileImageBytes;
  String? _profileImageExtension;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  /// Pick image from camera or gallery, then crop and update state
  Future<void> _pickAndCropImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 80,
      maxHeight: 512,
      maxWidth: 512,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Edit Photo',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile != null) {
      final bytes = await croppedFile.readAsBytes();
      setState(() {
        _profileImageBytes = bytes;
        _profileImageExtension = 'jpg';
      });
    }
  }

  /// Show option dialog for camera/gallery
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndCropImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndCropImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAuthSuccess(UserCredential result) async {
    // 1. Force the custom backend token exchange to initialize the backend User Schema immediately
    await BackendService.syncCustomTokens();

    if (widget.data.username != null) {
      await AuthService.updateProfile(displayName: widget.data.username);
    }

    String? imageUrl;
    if (_profileImageBytes != null && result.user != null) {
      imageUrl = await MediaUploadService.uploadProfileImage(
        userId: result.user!.uid,
        data: _profileImageBytes!,
        fileExtension: _profileImageExtension ?? 'jpg',
      );
      widget.data.profileImagePath = imageUrl;
      // CRITICAL FIX: Update Firebase Auth Profile so new posts catch this URL immediately
      await AuthService.updateProfile(photoURL: imageUrl);
    }

    if (result.user != null) {
      await UserService.createUserProfile(
        uid: result.user!.uid,
        displayName: result.user!.displayName,
        photoURL: result.user!.photoURL,
        data: widget.data,
        profileImageUrl: imageUrl,
      );
      UserSession.update(
        id: result.user!.uid,
        name: result.user!.displayName ?? widget.data.username,
        avatar: imageUrl ?? result.user!.photoURL,
        location: widget.data.location,
      );
    }

    if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
    }
  }

  Future<void> _createAccount() async {
    try {
      UserCredential? result;
      try {
        result = await AuthService.signUpWithEmail(
          widget.data.email!,
          widget.data.password!,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('An account already exists with this email. Please log in instead.')),
          );
          return;
        } else {
          rethrow;
        }
      }

      if (result != null) {
        // BUG-032 FIX: Clear password immediately after Firebase auth creation
        // to minimize in-memory exposure for the rest of the app session.
        widget.data.password = null;
        await _handleAuthSuccess(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create account or sign in')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(safeErrorMessage(e, fallback: 'Account creation failed. Please try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // CircleAvatar shows selected image, tap to change
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[300],
                backgroundImage: _profileImageBytes != null
                    ? MemoryImage(_profileImageBytes!)
                    : null,
                child: _profileImageBytes == null
                    ? const Icon(Icons.add_a_photo,
                        size: 40, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            const Text("Add profile photo (optional)"),
            const Spacer(),
            PrimaryButton(
              text: _isLoading ? "Creating Account..." : "Complete Signup",
              onTap: _isLoading ? () {} : () {
                if (widget.data.email == null || widget.data.password == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Missing email or password')),
                  );
                  return;
                }

                setState(() {
                  _isLoading = true;
                });

                _createAccount();
              },
            ),
          ],
        ),
      ),
    );
  }
}
