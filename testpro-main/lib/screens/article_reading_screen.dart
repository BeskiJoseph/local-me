import 'package:flutter/material.dart';
import '../models/post.dart';
import '../utils/proxy_helper.dart';
import '../shared/widgets/user_avatar.dart';

class ArticleReadingScreen extends StatefulWidget {
  final Post article;

  const ArticleReadingScreen({super.key, required this.article});

  @override
  State<ArticleReadingScreen> createState() => _ArticleReadingScreenState();
}

class _ArticleReadingScreenState extends State<ArticleReadingScreen> {
  final PageController _pageController = PageController();
  bool _isStudyMode = false;
  int _currentPageIndex = 0;
  List<String> _textPages = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Simple heuristic text chunker to simulate book pages
  List<String> _chunkText(String text, int maxCharsPerPage) {
    if (text.isEmpty) return ["(No content)"];
    
    final List<String> pages = [];
    final paragraphs = text.split('\n\n');
    String currentPage = '';

    for (final p in paragraphs) {
      // If a single paragraph is huge, we might just have to add it anyway
      // to avoid complex word-wrapping metrics, but normally it splits fine.
      if ((currentPage.length + p.length) > maxCharsPerPage && currentPage.isNotEmpty) {
        pages.add(currentPage.trim());
        currentPage = p + '\n\n';
      } else {
        currentPage += p + '\n\n';
      }
    }
    
    if (currentPage.trim().isNotEmpty) {
      pages.add(currentPage.trim());
    }
    
    return pages.isEmpty ? [text] : pages;
  }

  void _toggleStudyMode() {
    setState(() {
      _isStudyMode = !_isStudyMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Theme configurations
    final bgColor = _isStudyMode ? const Color(0xFF1E1E1E) : const Color(0xFFF9F9F4); // Paper color
    final textColor = _isStudyMode ? const Color(0xFFE0E0E0) : const Color(0xFF2C2C2E);
    final secondaryTextColor = _isStudyMode ? const Color(0xFFA0A0A0) : const Color(0xFF757575);
    final iconColor = _isStudyMode ? Colors.white70 : Colors.black87;
    final appBarColor = _isStudyMode ? const Color(0xFF121212) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: iconColor),
        title: Text(
          widget.article.title,
          style: TextStyle(
            color: iconColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isStudyMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: iconColor,
            ),
            tooltip: 'Toggle Study Mode',
            onPressed: _toggleStudyMode,
          ),
          IconButton(
            icon: Icon(Icons.bookmark_border, color: iconColor),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Author Header
            Text(
              widget.article.title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.2,
                color: textColor,
                fontFamily: 'Georgia',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                UserAvatar(
                  imageUrl: widget.article.authorProfileImage,
                  name: widget.article.authorName,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By ${widget.article.authorName}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Published on ${_formatDate(widget.article.createdAt)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Main Cover Image (if any)
            if (widget.article.mediaUrl != null && widget.article.mediaType != 'document') ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  ProxyHelper.getUrl(widget.article.mediaUrl!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: _isStudyMode ? Colors.white10 : Colors.black12,
                    child: Icon(Icons.broken_image, color: secondaryTextColor),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Article Content (Text + Inline Images)
            ..._renderBody(widget.article.body, textColor, secondaryTextColor),

            const SizedBox(height: 60),
            Divider(color: secondaryTextColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.favorite_border, widget.article.likeCount.toString(), secondaryTextColor),
                _buildStatItem(Icons.mode_comment_outlined, widget.article.commentCount.toString(), secondaryTextColor),
                _buildStatItem(Icons.visibility_outlined, widget.article.viewCount.toString(), secondaryTextColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _renderBody(String text, Color textColor, Color secondaryTextColor) {
    if (text.isEmpty) return [Text("(No content)", style: TextStyle(color: textColor))];

    final List<Widget> widgets = [];
    final RegExp imageRegex = RegExp(r'!\[.*?\]\((.*?)\)');
    
    int lastMatchEnd = 0;
    for (final Match match in imageRegex.allMatches(text)) {
      // Add text before image
      if (match.start > lastMatchEnd) {
        final section = text.substring(lastMatchEnd, match.start).trim();
        if (section.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Text(
              section,
              style: TextStyle(
                fontSize: 18,
                height: 1.9,
                color: textColor,
                letterSpacing: 0.3,
                fontFamily: 'Georgia',
              ),
            ),
          ));
        }
      }

      // Add inline image
      final String url = match.group(1)!;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            ProxyHelper.getUrl(url),
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 120,
              width: double.infinity,
              color: _isStudyMode ? Colors.white10 : Colors.black12,
              child: Icon(Icons.broken_image, color: secondaryTextColor),
            ),
          ),
        ),
      ));
      
      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      final section = text.substring(lastMatchEnd).trim();
      if (section.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Text(
            section,
            style: TextStyle(
              fontSize: 18,
              height: 1.9,
              color: textColor,
              letterSpacing: 0.3,
              fontFamily: 'Georgia',
            ),
          ),
        ));
      }
    }

    return widgets;
  }


  Widget _buildStatItem(IconData icon, String count, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          count,
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
