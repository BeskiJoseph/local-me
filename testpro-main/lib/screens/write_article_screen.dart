import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../services/post_service.dart';
import '../services/backend_service.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../models/post.dart';
import '../utils/safe_error.dart';

/// A custom controller that styles Markdown-like syntax visually in the editor
class MarkdownEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    
    // Simple regex for bold, italic, and headings
    // This allows the user to see the styles while typing plain text/markdown
    text.splitMapJoin(
      RegExp(r'(\*\*.*?\*\*)|(_.*?_)|(#+ .*?\n)|(> .*?\n)'),
      onMatch: (Match match) {
        final String matchText = match[0]!;
        if (matchText.startsWith('**')) {
          children.add(TextSpan(
            text: matchText,
            style: style?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ));
        } else if (matchText.startsWith('_')) {
          children.add(TextSpan(
            text: matchText,
            style: style?.copyWith(fontStyle: FontStyle.italic),
          ));
        } else if (matchText.startsWith('#')) {
          children.add(TextSpan(
            text: matchText,
            style: style?.copyWith(
              fontWeight: FontWeight.w900, 
              fontSize: matchText.startsWith('##') ? 20 : 24,
              color: const Color(0xFF1E293B),
            ),
          ));
        } else if (matchText.startsWith('>')) {
          children.add(TextSpan(
            text: matchText,
            style: style?.copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
              backgroundColor: Colors.grey[100],
            ),
          ));
        } else {
          children.add(TextSpan(text: matchText, style: style));
        }
        return '';
      },
      onNonMatch: (String text) {
        children.add(TextSpan(text: text, style: style));
        return '';
      },
    );

    return TextSpan(style: style, children: children);
  }
}

class WriteArticleScreen extends StatefulWidget {
  const WriteArticleScreen({super.key});

  @override
  State<WriteArticleScreen> createState() => _WriteArticleScreenState();
}

class _WriteArticleScreenState extends State<WriteArticleScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _subtitleController = TextEditingController();
  final MarkdownEditingController _contentController = MarkdownEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _formatText(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    if (selection.start == -1) return;

    final selectedText = text.substring(selection.start, selection.end);
    
    // Toggle logic: If already formatted, remove it. Otherwise, add it.
    if (selectedText.startsWith(prefix) && selectedText.endsWith(suffix)) {
      final unformattedText = selectedText.substring(prefix.length, selectedText.length - suffix.length);
      final newText = text.replaceRange(selection.start, selection.end, unformattedText);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + unformattedText.length,
        ),
      );
    } else {
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '$prefix$selectedText$suffix',
      );
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + prefix.length + selectedText.length + suffix.length,
        ),
      );
    }
  }

  // Articles are text-only, no image picking needed
  Future<void> _pickImage() async {
    // Disabled - articles don't support images
    return;
  }

  Future<void> _submit() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an article title')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write some content')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Get GPS coordinates so the article appears in the local feed
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('Location detection failed (optional): $e');
      }

      // Articles are text-only, no media upload
      final responseId = await PostService.createPost(
        title: title,
        body: content,
        category: 'Article',
        mediaUrl: null,
        mediaType: 'none',
        city: LocationService.getLocationString(),
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      if (!mounted) return;

      if (responseId.isNotEmpty) {
        // Fetch new post and emit for instant display
        BackendService.getPost(responseId).then((response) {
          if (response.success && response.data != null) {
            final post = Post.fromJson(response.data!);
            PostService.emit(FeedEvent(FeedEventType.postCreated, post));
          }
        });
        
        if (!mounted) return;
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Article posted successfully!')),
        );
      } else {
        throw Exception('Failed to post article');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error posting article: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(safeErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151), size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Write Article',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            fontSize: 19,
            letterSpacing: -0.3,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            child: SizedBox(
              height: 34,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D6D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'Post +',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- ARTICLE TITLE ---
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                      fontFamily: 'serif', 
                      height: 1.1,
                      letterSpacing: -1.0,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Article Title',
                      hintStyle: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w800),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- SUBTITLE BOX ---
                  SizedBox(
                    height: 50,
                    child: TextField(
                      controller: _subtitleController,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF4B5563)),
                      decoration: InputDecoration(
                        hintText: 'Subtitle (optional)',
                        hintStyle: const TextStyle(fontSize: 15, color: Color(0xFFCBD5E0)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        filled: true,
                        fillColor: const Color(0xFFFBFBFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // --- RICH TEXT TOOLBAR ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolbarIcon(
                            label: 'B', 
                            isBold: true,
                            onTap: () => _formatText('**', '**'),
                          ),
                          _ToolbarIcon(
                            icon: Icons.format_italic,
                            onTap: () => _formatText('_', '_'),
                          ),
                          _ToolbarIcon(
                            label: 'H', 
                            onTap: () => _formatText('# ', '\n'),
                          ),
                          _ToolbarIcon(
                            label: 'H2', 
                            onTap: () => _formatText('## ', '\n'),
                          ),
                          _ToolbarIcon(
                            icon: Icons.format_list_bulleted,
                            onTap: () => _formatText('- ', '\n'),
                          ),
                          _ToolbarIcon(
                            icon: Icons.format_list_numbered,
                            onTap: () => _formatText('1. ', '\n'),
                          ),
                          _ToolbarIcon(
                            icon: Icons.format_quote,
                            onTap: () => _formatText('> ', '\n'),
                          ),
                          _ToolbarIcon(
                            icon: Icons.link,
                            onTap: () => _formatText('[', '](url)'),
                          ),
                          // Note: Articles are text-only, no images allowed
                          _ToolbarIcon(
                            icon: Icons.text_fields,
                            onTap: () {},
                          ),
                          _ToolbarIcon(
                            icon: Icons.more_horiz,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- EDITOR AREA ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Articles are text-only - no image upload
                        // Text Editor
                        TextField(
                          controller: _contentController,
                          maxLines: null,
                          minLines: 15,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.7,
                            color: Color(0xFF334155),
                            fontFamily: 'Georgia',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Start writing your article...',
                            hintStyle: TextStyle(color: Color(0xFFCBD5E0)),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple toolbar icon widget
class _ToolbarIcon extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final bool isBold;
  final VoidCallback onTap;

  const _ToolbarIcon({
    this.icon,
    this.label,
    this.isBold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: label != null
            ? Text(
                label!,
                style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  fontSize: 15,
                  color: const Color(0xFF475569),
                ),
              )
            : Icon(icon, size: 18, color: const Color(0xFF475569)),
      ),
    );
  }
}
