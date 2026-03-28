import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/post.dart';
import '../../utils/proxy_helper.dart';
import '../../screens/video_player_screen.dart';

class PostMediaDisplay extends StatefulWidget {
  final Post post;

  const PostMediaDisplay({super.key, required this.post});

  @override
  State<PostMediaDisplay> createState() => _PostMediaDisplayState();
}

class _PostMediaDisplayState extends State<PostMediaDisplay> {
  bool _imageLoading = true;

  void _handleMediaTap() {
    if (widget.post.mediaUrl == null) return;

    if (widget.post.mediaType == 'video') {
      // Open video player screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(post: widget.post),
        ),
      );
    } else if (widget.post.mediaType == 'document') {
      // Open document URL
      final url = Uri.parse(ProxyHelper.getUrl(widget.post.mediaUrl!));
      launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // Open image in full screen
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
                        fit: BoxFit.contain,
                        maxHeightDiskCache: 2048,
                        maxWidthDiskCache: 2048,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white, size: 50),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.post.mediaUrl == null) return const SizedBox.shrink();

    final isVideo = widget.post.mediaType == 'video';
    final isDocument = widget.post.mediaType == 'document';
    
    if (isDocument) {
      return _buildDocumentCard();
    }

    final mediaUrl = widget.post.thumbnailUrl ?? widget.post.mediaUrl!;
    // Instagram-style: 4:5 for images (compact), 9:16 for videos (vertical)
    final aspectRatio = isVideo ? 9 / 16 : 4 / 5;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleMediaTap,
            child: Stack(
              children: [
                // Main Image/Video Thumbnail
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Loading Shimmer Effect
                      if (_imageLoading)
                        _ShimmerEffect(),
                      
                      // Actual Image
                      CachedNetworkImage(
                        imageUrl: ProxyHelper.getUrl(mediaUrl),
                        fit: BoxFit.cover,
                        maxHeightDiskCache: 1080,
                        maxWidthDiskCache: 1080,
                        memCacheWidth: 800,
                        memCacheHeight: 800,
                        placeholder: (context, url) => _ShimmerEffect(),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade100,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey.shade400,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Failed to load media',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Video Play Button Overlay
                if (isVideo)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 48,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Video Duration Badge
                if (isVideo)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.play_circle_filled,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'VIDEO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Tap to expand hint (subtle)
                if (!isVideo)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.zoom_out_map,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard() {
    final fileName = widget.post.mediaUrl?.split('/').last ?? 'Document';
    final extension = fileName.split('.').last.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: _handleMediaTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Color(0xFF3182CE),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extension == 'PDF' ? 'PDF Document' : 'Word Document',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to view document',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                color: Color(0xFFCBD5E0),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerEffect extends StatefulWidget {
  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-1.0, -0.5),
              end: const Alignment(1.0, 0.5),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade50,
                Colors.grey.shade200,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ].map((v) => v.clamp(0.0, 1.0)).toList(),
            ),
          ),
        );
      },
    );
  }
}
