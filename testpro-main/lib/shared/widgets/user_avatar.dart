import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/proxy_helper.dart';

/// A reusable user avatar widget with network image and initials fallback.
///
/// Replaces 13+ manual CircleAvatar implementations across the codebase.
/// Automatically handles:
///  - Network image loading via ProxyHelper
///  - Initials fallback when no image is available
///  - Configurable size, background color, and text style
///  - Optional gradient border
class UserAvatar extends StatelessWidget {
  /// The URL of the user's profile image. Can be null.
  final String? imageUrl;

  /// The user's display name. Used to generate fallback initials.
  final String name;

  /// Radius of the CircleAvatar. Default is 20.
  final double radius;

  /// Background color when showing initials. Default is grey[200].
  final Color? backgroundColor;

  /// Text color for initials. Default is Colors.grey.
  final Color? initialsColor;

  /// Font size for initials. Auto-calculated from radius if null.
  final double? initialsFontSize;

  /// Whether to show a gradient border around the avatar.
  final bool showGradientBorder;

  /// Gradient colors for the border (only used if [showGradientBorder] is true).
  final List<Color> gradientColors;

  /// Width of the gradient border. Default is 2.
  final double borderWidth;

  const UserAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 20,
    this.backgroundColor,
    this.initialsColor,
    this.initialsFontSize,
    this.showGradientBorder = false,
    this.gradientColors = const [Color(0xFF667EEA), Color(0xFF764BA2)],
    this.borderWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Semantics(
      label: 'Avatar of $name',
      child: CircleAvatar(
        radius: showGradientBorder ? radius - borderWidth : radius,
        backgroundColor: backgroundColor ?? Colors.grey[200],
        backgroundImage: imageUrl != null
            ? CachedNetworkImageProvider(
                ProxyHelper.getUrl(imageUrl!),
                maxWidth: (radius * 4).toInt(),
              )
            : null,
        child: imageUrl == null ? _buildInitials() : null,
      ),
    );

    if (!showGradientBorder) return avatar;

    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: gradientColors),
      ),
      child: avatar,
    );
  }

  Widget _buildInitials() {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fontSize = initialsFontSize ?? (radius * 0.7);

    return Text(
      initial,
      style: TextStyle(
        color: initialsColor ?? Colors.grey,
        fontWeight: FontWeight.bold,
        fontSize: fontSize,
        fontFamily: 'Inter',
      ),
    );
  }
}
