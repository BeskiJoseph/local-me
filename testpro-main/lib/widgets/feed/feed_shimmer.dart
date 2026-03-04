import 'package:flutter/material.dart';

/// ============================================================
/// FEED SHIMMER — Skeleton loading cards for initial feed load.
/// Pure Flutter — no external shimmer/skeletonizer dependency.
/// ============================================================
class FeedShimmer extends StatefulWidget {
  final int itemCount;
  const FeedShimmer({super.key, this.itemCount = 4});

  @override
  State<FeedShimmer> createState() => _FeedShimmerState();
}

class _FeedShimmerState extends State<FeedShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading posts',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => _ShimmerCard(
              animationValue: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double animationValue;
  const _ShimmerCard({required this.animationValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header skeleton (avatar + name + time) ────────
          Row(
            children: [
              _shimmerCircle(44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 120, height: 12),
                    const SizedBox(height: 6),
                    _shimmerBox(width: 80, height: 10),
                  ],
                ),
              ),
              _shimmerBox(width: 30, height: 10),
            ],
          ),
          const SizedBox(height: 14),

          // ── Category chip skeleton ────────────────────────
          _shimmerBox(width: 72, height: 24, borderRadius: 20),
          const SizedBox(height: 12),

          // ── Title skeleton ───────────────────────────────
          _shimmerBox(width: double.infinity, height: 14),
          const SizedBox(height: 8),
          _shimmerBox(width: 200, height: 14),
          const SizedBox(height: 14),

          // ── Media skeleton ───────────────────────────────
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _shimmerBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 12,
            ),
          ),
          const SizedBox(height: 14),

          // ── Reaction row skeleton ────────────────────────
          Row(
            children: [
              _shimmerBox(width: 50, height: 12),
              const SizedBox(width: 16),
              _shimmerBox(width: 50, height: 12),
              const Spacer(),
              _shimmerBox(width: 24, height: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox({
    required double width,
    required double height,
    double borderRadius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: const [
            Color(0xFFEBEBF4),
            Color(0xFFF4F4F8),
            Color(0xFFEBEBF4),
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1.0 + 2 * animationValue, 0),
          end: Alignment(1.0 + 2 * animationValue, 0),
        ),
      ),
    );
  }

  Widget _shimmerCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: const [
            Color(0xFFEBEBF4),
            Color(0xFFF4F4F8),
            Color(0xFFEBEBF4),
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1.0 + 2 * animationValue, 0),
          end: Alignment(1.0 + 2 * animationValue, 0),
        ),
      ),
    );
  }
}

/// Simple single shimmer bar for inline use (e.g. media loading placeholder)
class ShimmerPlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 0,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFEBEBF4),
                Color(0xFFF4F4F8),
                Color(0xFFEBEBF4),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1.0 + 2 * _controller.value, 0),
              end: Alignment(1.0 + 2 * _controller.value, 0),
            ),
          ),
        );
      },
    );
  }
}
