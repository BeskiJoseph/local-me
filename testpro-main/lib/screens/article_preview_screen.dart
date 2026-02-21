import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class ArticlePreviewScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String content;
  final String tags;

  const ArticlePreviewScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.content,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Preview',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? 'Untitled Article' : title,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
                fontFamily: 'Serif',
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF8A8A8A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            Text(
              content.isEmpty ? 'No content provided.' : content,
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFF2D2D2D),
                height: 1.6,
                fontFamily: 'Serif',
              ),
            ),
            const SizedBox(height: 32),
            if (tags.isNotEmpty)
              Wrap(
                spacing: 8,
                children: tags.split(',').map((tag) => Chip(
                  label: Text(tag.trim()),
                  backgroundColor: const Color(0xFFF0F2F5),
                  side: BorderSide.none,
                )).toList(),
              ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D6D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Back to Edit',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
