import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final String expandText;
  final String collapseText;
  final TextStyle? linkStyle;

  const ExpandableText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 2,
    this.expandText = 'more',
    this.collapseText = 'less',
    this.linkStyle,
  });

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    final linkStyle = widget.linkStyle ?? 
        const TextStyle(
          color: Color(0xFF8A8A8A),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(
          text: widget.text,
          style: defaultStyle,
        );

        final textPainter = TextPainter(
          text: textSpan,
          maxLines: widget.maxLines,
          textDirection: ui.TextDirection.ltr,
        );

        textPainter.layout(maxWidth: constraints.maxWidth);

        if (!textPainter.didExceedMaxLines) {
          return RichText(text: textSpan);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: textSpan,
              maxLines: _isExpanded ? null : widget.maxLines,
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Text(
                _isExpanded ? widget.collapseText : widget.expandText,
                style: linkStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}
