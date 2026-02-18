import 'package:flutter/material.dart';

/// A reusable empty state widget for screens with no content.
///
/// Replaces 8+ inline empty state implementations across the codebase.
/// Configurable with icon, title, subtitle, and an optional action button.
class EmptyStateWidget extends StatelessWidget {
  /// The icon to display. Default is an info icon.
  final IconData icon;

  /// Primary title text.
  final String title;

  /// Optional subtitle text displayed below the title.
  final String? subtitle;

  /// Size of the icon. Default is 64.
  final double iconSize;

  /// Color of the icon. Default is grey.
  final Color? iconColor;

  /// Optional action button label. If provided, a button is shown.
  final String? actionLabel;

  /// Callback when the action button is pressed.
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconSize = 64,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
