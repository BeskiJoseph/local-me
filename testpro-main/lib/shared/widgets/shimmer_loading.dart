import 'package:flutter/material.dart';

/// A reusable shimmer loading effect widget.
///
/// Extracted from `widgets/post_card.dart`. Use this anywhere
/// a shimmering placeholder loading animation is needed.
class ShimmerEffect extends StatefulWidget {
  /// Optional child widget to apply shimmer to.
  final Widget? child;

  /// Width of the shimmer container. Uses parent width if null.
  final double? width;

  /// Height of the shimmer container.
  final double? height;

  /// Border radius for the shimmer container.
  final double borderRadius;

  /// Whether the shimmer is circular.
  final bool isCircular;

  const ShimmerEffect({
    super.key,
    this.child,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.isCircular = false,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
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
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.isCircular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircular
                ? null
                : BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: const Alignment(-1.0, -0.5),
              end: const Alignment(1.0, 0.5),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade50,
                Colors.grey.shade200,
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Convenience widget for shimmer placeholder boxes.
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

/// Convenience widget for shimmer placeholder circles.
class ShimmerCircle extends StatelessWidget {
  final double radius;

  const ShimmerCircle({super.key, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      width: radius * 2,
      height: radius * 2,
      isCircular: true,
    );
  }
}
