import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../utils/media_utility.dart';

class PostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;

  const PostVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
  });

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    // ✅ Sanitize video URL through proxy
    final proxiedUrl = MediaUtility.getProxyUrl(widget.videoUrl);
    
    _controller = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl));
    
    try {
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _controller.setLooping(true);
          _controller.setVolume(0); // Start muted for feed
        });
      }
    } catch (e) {
      debugPrint('🚨 Video Player Error: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 250,
        color: Colors.grey[100],
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 8),
            Text('Video unavailable', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        height: 250,
        color: Colors.grey[50],
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        // Auto-play when 80% visible, pause when not
        if (info.visibleFraction > 0.8) {
          _controller.play();
        } else {
          _controller.pause();
        }
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              if (!_controller.value.isPlaying)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
