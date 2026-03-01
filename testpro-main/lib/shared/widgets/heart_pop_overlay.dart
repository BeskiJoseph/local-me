import 'package:flutter/material.dart';

class HeartPopOverlay extends StatefulWidget {
  const HeartPopOverlay({super.key});

  @override
  State<HeartPopOverlay> createState() => _HeartPopOverlayState();
}

class _HeartPopOverlayState extends State<HeartPopOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.1, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.1), weight: 10),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack));

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _controller.forward().then((_) {
      if (mounted) _controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: const Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: 100,
            shadows: [
              Shadow(
                blurRadius: 20.0,
                color: Colors.black45,
                offset: Offset(0, 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
