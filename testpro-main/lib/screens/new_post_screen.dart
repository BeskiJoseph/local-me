import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import 'create_event_screen.dart';
import 'write_article_screen.dart';
import '../services/auth_service.dart';
import '../services/media_upload_service.dart';
import '../services/backend_service.dart';
import '../services/location_service.dart';
import '../services/user_service.dart';
import '../services/geocoding_service.dart';
import '../services/post_service.dart';
import '../models/post.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../shared/widgets/user_avatar.dart';
import '../core/session/user_session.dart';

class NewPostScreen extends StatefulWidget {
  const NewPostScreen({super.key});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _contentController = TextEditingController();
  String? _currentLocation = 'Detecting location...';
  bool _isSubmitting = false;

  // Media state
  Uint8List? _mediaBytes;
  Uint8List? _thumbnailBytes;
  String? _mediaExtension;
  String _mediaType = 'image';
  bool _isGeneratingThumbnail = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentLocation = LocationService.getLocationString();
  }

  Future<void> _detectLocation() async {
    try {
      final user = AuthService.currentUser;
      if (user != null) {
        final profile = await UserService.getUserProfile(user.uid);
        if (profile?.location != null && profile!.location!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _currentLocation = profile.location!.split(',')[0].trim();
            });
            return; // Use stored location from profile
          }
        }
      }

      // Fallback to fresh detection if profile location is missing
      final position = await Geolocator.getCurrentPosition();
      final place = await GeocodingService.getPlace(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLocation = place['city'] ?? 'Unknown Location';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocation = 'Unknown Location'; // Fallback
        });
      }
    }
  }

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Add Media',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickImage(source: ImageSource.camera);
                  _processMedia(file, 'image', 'jpg');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose Photo from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickImage(source: ImageSource.gallery);
                  _processMedia(file, 'image', 'jpg');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record Video'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickVideo(source: ImageSource.camera);
                  _processMedia(file, 'video', 'mp4');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Choose Video from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickVideo(source: ImageSource.gallery);
                  _processMedia(file, 'video', 'mp4');
                },
              ),
              // Camera and Gallery options available
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processMedia(XFile? file, String type, String extension) async {
    if (file == null) return;
    setState(() => _isGeneratingThumbnail = type == 'video');

    final bytes = await file.readAsBytes();
    Uint8List? thumbnailData;

    if (type == 'video') {
      try {
        final tempDir = await getTemporaryDirectory();
        final path = await VideoThumbnail.thumbnailFile(
          video: file.path,
          thumbnailPath: tempDir.path,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 640,
          quality: 75,
        );
        if (path != null) thumbnailData = await File(path).readAsBytes();
      } catch (e) {
        debugPrint('Thumbnail error: $e');
      }
    }

    setState(() {
      _mediaBytes = bytes;
      _thumbnailBytes = thumbnailData;
      _mediaType = type;
      _mediaExtension = extension;
      _isGeneratingThumbnail = false;
    });
  }

  Future<void> _submit() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    // Normal posts REQUIRE image or video - text only not allowed
    if (_mediaBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add an image or video to post')),
      );
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a caption')),
      );
      return;
    }

    if (_contentController.text.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content cannot exceed 500 characters.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    
    // Create temporary post for optimistic UI update
    final position = await Geolocator.getCurrentPosition();
    final tempPostId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create temporary post object
    final tempPost = Post(
      id: tempPostId,
      authorId: user.uid,
      authorName: user.displayName ?? user.email?.split('@')[0] ?? 'User',
      title: _contentController.text.trim(),
      body: _contentController.text.trim(),
      scope: 'local',
      mediaUrl: null, // Will be updated after upload
      mediaType: _mediaType,
      createdAt: DateTime.now(),
      likeCount: 0,
      commentCount: 0,
      latitude: position.latitude,
      longitude: position.longitude,
      city: _currentLocation,
      country: null,
      category: 'General',
      thumbnailUrl: null,
      authorProfileImage: user.photoURL,
      isEvent: false,
      attendeeCount: 0,
      isLiked: false,
      viewCount: 0,
    );
    
    // Emit event to show temporary post immediately
    debugPrint('📤 Emitting temporary post event: ${tempPost.id}');
    PostService.emit(FeedEvent(FeedEventType.postCreated, tempPost));
    
    try {
      final String postId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Upload media
      String? mediaUrl;
      String? thumbnailUrl;
      if (_mediaBytes != null) {
        mediaUrl = await MediaUploadService.uploadPostMedia(
          postId: postId,
          data: _mediaBytes!,
          fileExtension: _mediaExtension ?? 'jpg',
          mediaType: _mediaType,
        );
        if (_mediaType == 'video' && _thumbnailBytes != null) {
          thumbnailUrl = await MediaUploadService.uploadPostMedia(
            postId: postId,
            data: _thumbnailBytes!,
            fileExtension: 'jpg',
            mediaType: 'image',
          );
        }
      }

      // Update temp post with media URLs
      final updatedTempPost = Post(
        id: tempPostId,
        authorId: user.uid,
        authorName: user.displayName ?? user.email?.split('@')[0] ?? 'User',
        title: _contentController.text.trim(),
        body: _contentController.text.trim(),
        scope: 'local',
        mediaUrl: mediaUrl,
        mediaType: _mediaType,
        createdAt: DateTime.now(),
        likeCount: 0,
        commentCount: 0,
        latitude: position.latitude,
        longitude: position.longitude,
        city: _currentLocation,
        country: null,
        category: 'General',
        thumbnailUrl: thumbnailUrl,
        authorProfileImage: user.photoURL,
        isEvent: false,
        attendeeCount: 0,
        isLiked: false,
        viewCount: 0,
      );
      
      // Emit updated temp post with media URL
      debugPrint('📤 Emitting updated temporary post event with media: ${updatedTempPost.id}');
      debugPrint('📤 Media URL: ${updatedTempPost.mediaUrl}');
      PostService.emit(FeedEvent(FeedEventType.postCreated, updatedTempPost));

      // 2. Create post via PostService (handles backend call + event emission)
      final createdPostId = await PostService.createPost(
        title: _contentController.text.trim(),
        body: _contentController.text.trim(),
        city: _currentLocation,
        category: 'General',
        mediaUrl: mediaUrl,
        mediaType: _mediaType,
        thumbnailUrl: thumbnailUrl,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;
      
      if (createdPostId.isNotEmpty) {
        debugPrint('✅ Post created successfully with ID: $createdPostId');
        // Emit final post to replace temp post
        // The backend service will emit the real post event
        Navigator.pop(context, true);
      } else {
        debugPrint('❌ Post creation failed');
        // Remove temp post on failure
        PostService.emit(FeedEvent(FeedEventType.postDeleted, tempPostId));
        throw Exception('Failed to create post');
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      // Remove temp post on error
      PostService.emit(FeedEvent(FeedEventType.postDeleted, tempPostId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final String username = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';
    final String? profileImg = user?.photoURL;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Create Post',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: _PostBtn(onTap: _isSubmitting ? null : _submit),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── User Header ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  ValueListenableBuilder(
                    valueListenable: UserSession.current,
                    builder: (context, sessionData, _) {
                      final displayAvatar = sessionData?.avatarUrl ?? profileImg;
                      final displayName = sessionData?.displayName ?? username;
                      return UserAvatar(imageUrl: displayAvatar, name: displayName, radius: 24);
                    }
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "What's on your mind?",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8A8A8A),
                          fontFamily: AppTheme.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Color(0xFF8A8A8A)),
                          const SizedBox(width: 4),
                          Text(
                            _currentLocation ?? '',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.public, size: 14, color: Color(0xFF8A8A8A)),
                          const SizedBox(width: 4),
                          const Text(
                            'Public',
                            style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Minimalist Caption Input ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _contentController,
                maxLines: null, // Auto-expand
                minLines: 1,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF1A1A1A),
                  fontFamily: AppTheme.fontFamily,
                ),
                decoration: const InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(
                    fontSize: 18,
                    color: Color(0xFFBCBCBC),
                    fontFamily: AppTheme.fontFamily,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Action Pills ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _CompactActionPill(
                    icon: Icons.camera_alt,
                    label: 'Photo/Video',
                    iconColor: const Color(0xFF2E7D6A),
                    onTap: _pickMedia,
                  ),
                  const SizedBox(width: 8),
                  _CompactActionPill(
                    icon: Icons.article_outlined,
                    label: 'Article',
                    iconColor: const Color(0xFF4285F4),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WriteArticleScreen()),
                      );
                      if (result == true && mounted) {
                        Navigator.pop(context, true); // Return to Home with refresh signal
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _CompactActionPill(
                    icon: Icons.calendar_today,
                    label: 'Event',
                    iconColor: const Color(0xFFEA4335),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                      );
                      if (result == true && mounted) {
                        Navigator.pop(context, true); // Return to Home with refresh signal
                      }
                    },
                  ),
                ],
              ),
            ),

            if (_mediaBytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Media Preview',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _mediaBytes = null),
                          child: const Text(
                            'Remove',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEA4335),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        (_mediaType == 'video' ? (_thumbnailBytes ?? _mediaBytes!) : _mediaBytes!),
                        height: 320, // Even more prominent
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Compact Action Pill for a cleaner look
// ─────────────────────────────────────────────────────────────
class _CompactActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _CompactActionPill({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
                fontFamily: AppTheme.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostBtn extends StatelessWidget {
  final VoidCallback? onTap;
  const _PostBtn({this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isLoading = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D6A).withValues(alpha: isLoading ? 0.6 : 1.0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                'Post',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  fontFamily: AppTheme.fontFamily,
                ),
              ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
                fontFamily: AppTheme.fontFamily,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}


