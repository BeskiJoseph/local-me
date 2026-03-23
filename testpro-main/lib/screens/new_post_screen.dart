import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'create_event_screen.dart';
import 'write_article_screen.dart';
import '../services/auth_service.dart';
import '../services/media_upload_service.dart';
import '../services/location_service.dart';
import '../services/user_service.dart';
import '../services/geocoding_service.dart';
import '../services/post_service.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';

import '../shared/widgets/user_avatar.dart';
import '../core/session/user_session.dart';
import '../core/utils/haptic_service.dart';
import '../utils/safe_error.dart';

class NewPostScreen extends StatefulWidget {
  const NewPostScreen({super.key});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  String? _currentLocation = 'Detecting location...';
  bool _isSubmitting = false;
  bool _cancelUpload = false;

  // Media state
  Uint8List? _mediaBytes;
  Uint8List? _thumbnailBytes;
  String? _mediaExtension;
  String _mediaType = 'image';
  bool _isGeneratingThumbnail = false;
  final ImagePicker _picker = ImagePicker();

  // Upload progress state
  String _uploadStep = '';
  double _uploadProgress = 0.0;

  // Character limit
  static const int _maxChars = 2000;

  // track if user has made any edits (for draft protection)
  bool get _hasDraft =>
      _contentController.text.isNotEmpty || _mediaBytes != null;

  // Post button enabled only when form is valid
  bool get _canPost =>
      !_isSubmitting &&
      _mediaBytes != null &&
      _contentController.text.trim().isNotEmpty &&
      (_mediaType == 'document' || _contentController.text.length <= _maxChars);

  @override
  void initState() {
    super.initState();
    _currentLocation = LocationService.getLocationString();
    _contentController.addListener(() => setState(() {}));
    // Enrich location from profile if available
    _detectLocation();
    // Auto-focus caption field after build
    Future.microtask(() {
      if (mounted) _captionFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _captionFocus.dispose();
    super.dispose();
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

  // ── Draft Protection ─────────────────────────────────────────
  Future<bool> _onWillPop() async {
    if (!_hasDraft || _isSubmitting) return true;
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Discard Post?',
          style: TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You have unsaved changes. Are you sure you want to go back?',
          style: TextStyle(fontFamily: AppTheme.fontFamily, color: Color(0xFF6E6E73)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing', style: TextStyle(color: Color(0xFF8A8A8A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Color(0xFFEA4335), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return shouldDiscard ?? false;
  }

  // ── Media Picker ─────────────────────────────────────────────
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
                  _processMedia(file, 'image');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose Photo from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickImage(source: ImageSource.gallery);
                  _processMedia(file, 'image');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record Video'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickVideo(
                    source: ImageSource.camera,
                    maxDuration: const Duration(seconds: 60),
                  );
                  _processMedia(file, 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Choose Video from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(seconds: 60),
                  );
                  _processMedia(file, 'video');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Resolve real file extension from path ────────────────────
  String _resolveExtension(String path, String fallback) {
    final segments = path.split('.');
    if (segments.length > 1) {
      final ext = segments.last.toLowerCase();
      const validImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif'];
      const validVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'];
      const validDoc = ['pdf', 'doc', 'docx'];
      if (validImage.contains(ext) || validVideo.contains(ext) || validDoc.contains(ext)) return ext;
    }
    return fallback;
  }

  Future<void> _processMedia(XFile? file, String type) async {
    if (file == null) return;

    // Resolve real extension from file path
    final extension = _resolveExtension(file.path, type == 'image' ? 'jpg' : 'mp4');

    // Check file size before proceeding (100MB limit)
    final fileLength = await file.length();
    const maxSizeBytes = 100 * 1024 * 1024; // 100MB
    if (fileLength > maxSizeBytes) {
      if (mounted) {
        _showErrorSnackBar(
          'File too large (${(fileLength / 1024 / 1024).toStringAsFixed(1)}MB). Maximum: 100MB.',
        );
      }
      return;
    }

    // Additional video validation: reject videos that are too large for upload
    if (type == 'video' && fileLength > 50 * 1024 * 1024) {
      if (mounted) {
        _showErrorSnackBar(
          'Video is ${(fileLength / 1024 / 1024).toStringAsFixed(1)}MB. Maximum video size: 50MB.',
        );
      }
      return;
    }

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
      if (kDebugMode) debugPrint('Thumbnail error: $e');
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

  // ── User-friendly error SnackBar ─────────────────────────────
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontFamily: AppTheme.fontFamily))),
          ],
        ),
        backgroundColor: const Color(0xFFEA4335),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }


  // ── Submit with Progress ─────────────────────────────────────
  Future<void> _submit() async {
    // Double-post guard
    if (_isSubmitting) return;

    final user = AuthService.currentUser;
    if (user == null) return;

    // Normal posts REQUIRE image or video - text only not allowed
    if (_mediaBytes == null) {
      _showErrorSnackBar('Please add an image or video to post');
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      _showErrorSnackBar('Please add a caption');
      return;
    }

    if (_contentController.text.length > _maxChars) {
      _showErrorSnackBar('Caption cannot exceed $_maxChars characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _cancelUpload = false;
      _uploadStep = 'Preparing...';
      _uploadProgress = 0.0;
    });

    try {
      // Step 1: Get position
      setState(() {
        _uploadStep = 'Getting location...';
        _uploadProgress = 0.1;
      });
      final position = await Geolocator.getCurrentPosition();
      if (_cancelUpload) throw _UploadCancelled();

      final String postId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

      // Step 2: Upload media
      String? mediaUrl;
      String? thumbnailUrl;
      if (_mediaBytes != null) {
        setState(() {
          _uploadStep = 'Uploading ${_mediaType == "video" ? "video" : (_mediaType == "document" ? "document" : "photo")}...';
          _uploadProgress = 0.3;
        });
        if (_cancelUpload) throw _UploadCancelled();
        final uploadResult = await MediaUploadService.uploadPostMedia(
          postId: postId,
          data: _mediaBytes!,
          fileExtension: _mediaExtension ?? 'jpg',
          mediaType: _mediaType,
        );
        mediaUrl = uploadResult?['url'] as String?;
        setState(() => _uploadProgress = 0.6);

        if (_mediaType == 'video' && _thumbnailBytes != null) {
          setState(() => _uploadStep = 'Uploading thumbnail...');
          final thumbResult = await MediaUploadService.uploadPostMedia(
            postId: postId,
            data: _thumbnailBytes!,
            fileExtension: 'jpg',
            mediaType: 'image',
          );
          thumbnailUrl = thumbResult?['url'] as String?;
        }
        setState(() => _uploadProgress = 0.75);
      }

      if (_cancelUpload) throw _UploadCancelled();

      // Step 3: Create post
      setState(() {
        _uploadStep = 'Publishing...';
        _uploadProgress = 0.85;
      });
      final post = await PostService.createPost(
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

      if (post.id.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ Post created successfully with ID: ${post.id}');
        setState(() {
          _uploadStep = 'Done!';
          _uploadProgress = 1.0;
        });
        HapticService.success();
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.pop(context, true);
      } else {
        if (kDebugMode) debugPrint('❌ Post creation failed');
        throw Exception('Failed to create post');
      }
    } catch (e) {
      if (e is _UploadCancelled) {
        // User cancelled — silent cleanup
        if (kDebugMode) debugPrint('⚠️ Upload cancelled by user');
      } else {
        if (kDebugMode) debugPrint('Submit error: $e');
        if (mounted) {
          _showErrorSnackBar(safeErrorMessage(e));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _cancelUpload = false;
          _uploadStep = '';
          _uploadProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final String username = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';
    final String? profileImg = user?.photoURL;
    final int charCount = _contentController.text.length;
    final bool isOverLimit = charCount > _maxChars;

    return PopScope(
      canPop: !_hasDraft || _isSubmitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _onWillPop();
        if (shouldLeave && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
            onPressed: () async {
              if (_hasDraft && !_isSubmitting) {
                final shouldLeave = await _onWillPop();
                if (shouldLeave && mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
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
              child: _PostBtn(
                onTap: _canPost ? _submit : null,
                isLoading: _isSubmitting,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Upload Progress Bar ────────────────────────────
            if (_isSubmitting)
              _UploadProgressBar(
                step: _uploadStep,
                progress: _uploadProgress,
                onCancel: () {
                  setState(() => _cancelUpload = true);
                },
              ),

            Expanded(
              child: SingleChildScrollView(
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

                    // ── Caption Input ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _contentController,
                        focusNode: _captionFocus,
                        maxLines: null, // Auto-expand
                        minLines: 1,
                        enabled: !_isSubmitting,
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

                    // ── Character Counter ──────────────────────────────
                    if (charCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$charCount / $_maxChars',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppTheme.fontFamily,
                              color: isOverLimit
                                  ? const Color(0xFFEA4335)
                                  : charCount > _maxChars * 0.8
                                      ? const Color(0xFFFFA000)
                                      : const Color(0xFFBCBCBC),
                            ),
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
                            onTap: _isSubmitting ? () {} : _pickMedia,
                          ),
                          const SizedBox(width: 8),
                          _CompactActionPill(
                            icon: Icons.article_outlined,
                            label: 'Article',
                            iconColor: const Color(0xFF4285F4),
                            onTap: _isSubmitting
                                ? () {}
                                : () async {
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
                            onTap: _isSubmitting
                                ? () {}
                                : () async {
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

                    // ── Media Preview ─────────────────────────────────
                    if (_isGeneratingThumbnail)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D6A)),
                              ),
                              SizedBox(height: 8),
                              Text('Generating thumbnail...', style: TextStyle(fontSize: 12, color: Color(0xFF8A8A8A))),
                            ],
                          ),
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
                                Text(
                                  '${_mediaType == "video" ? "Video" : "Photo"} Preview',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8A8A8A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // File size badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F0F0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatFileSize(_mediaBytes!.length),
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A), fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const Spacer(),
                                // Remove button (red icon)
                                GestureDetector(
                                  onTap: _isSubmitting ? null : () => setState(() {
                                    _mediaBytes = null;
                                    _thumbnailBytes = null;
                                    _mediaExtension = null;
                                    _mediaType = 'image';
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.close, size: 14, color: Color(0xFFEA4335)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Remove',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFEA4335),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Media preview with play overlay for video
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_mediaType == 'document')
                                  Container(
                                    height: 120,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.description, color: Color(0xFF4285F4), size: 40),
                                        const SizedBox(width: 12),
                                        Flexible(
                                          child: Text(
                                            'Selected: ${_mediaExtension?.toUpperCase() ?? "Document"}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.memory(
                                      (_mediaType == 'video' ? (_thumbnailBytes ?? _mediaBytes!) : _mediaBytes!),
                                      height: 320,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                // Play icon overlay for video
                                if (_mediaType == 'video')
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 40),
                    // Keyboard-safe padding
                    SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// ─────────────────────────────────────────────────────────────
// Upload Progress Bar
// ─────────────────────────────────────────────────────────────
class _UploadProgressBar extends StatelessWidget {
  final String step;
  final double progress;
  final VoidCallback? onCancel;

  const _UploadProgressBar({required this.step, required this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF2E7D6A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6E6E73),
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E7D6A),
                  fontFamily: AppTheme.fontFamily,
                ),
              ),
              if (onCancel != null) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onCancel,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEA4335),
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE8E8E8),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D6A)),
            ),
          ),
        ],
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
  final bool isLoading;
  const _PostBtn({this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onTap == null && !isLoading;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D6A).withValues(alpha: isDisabled ? 0.4 : 1.0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                'Post',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: isDisabled ? 0.7 : 1.0),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  fontFamily: AppTheme.fontFamily,
                ),
              ),
      ),
    );
  }
}


/// Sentinel exception for user-cancelled uploads
class _UploadCancelled implements Exception {}
