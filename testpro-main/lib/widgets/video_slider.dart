import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoSlider extends StatefulWidget {
  const VideoSlider({super.key});

  @override
  State<VideoSlider> createState() => _VideoSliderState();
}

class _VideoSliderState extends State<VideoSlider> {
  final List<String> videos = [
    'assets/videos/V1.mp4',
    'assets/videos/V2.mp4',
    'assets/videos/V3.mp4',
  ];

  late PageController _pageController;
  final List<VideoPlayerController> _controllers = [];
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(); // full width
    _initVideos();
    // Disable auto-scroll for now to avoid PageController attachment issues
    // _autoScroll() will be called when needed
  }

  void _initVideos() {
    for (var video in videos) {
      final controller = VideoPlayerController.asset(video)
        ..initialize().then((_) {
          setState(() {});
        })
        ..setLooping(true);

      _controllers.add(controller);
    }

    _controllers.first.play();
  }

  void _autoScroll() async {
    // Add a small delay to ensure PageView is fully attached
    await Future.delayed(const Duration(milliseconds: 100));
    
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      
      try {
        // Only animate if page controller is attached to PageView and mounted
        if (mounted && _pageController.hasClients) {
          currentIndex = (currentIndex + 1) % videos.length;

          await _pageController.animateToPage(
            currentIndex,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );

          for (int i = 0; i < _controllers.length; i++) {
            if (i < _controllers.length) {
              i == currentIndex
                  ? _controllers[i].play()
                  : _controllers[i].pause();
            }
          }
        }
      } catch (e) {
        // Silently catch errors if PageView is disposed
        debugPrint('Video slider auto-scroll error: $e');
        break;
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final controller = _controllers[index];

        if (!controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        return AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        );
      },
    );
  }
}
