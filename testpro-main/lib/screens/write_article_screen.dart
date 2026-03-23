import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../services/post_service.dart';
import '../services/backend_service.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../models/post.dart';
import '../utils/safe_error.dart';
import 'package:testpro/core/events/feed_events.dart';
import 'package:file_picker/file_picker.dart';
import '../services/media_upload_service.dart';
import '../utils/proxy_helper.dart';
import 'dart:typed_data';

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

class ArticleBlock {
  final String type; // 'text' or 'image'
  String content;
  TextEditingController? controller;
  FocusNode? focusNode;

  ArticleBlock({required this.type, required this.content}) {
    if (type == 'text') {
      controller = TextEditingController(text: content);
      focusNode = FocusNode();
    }
  }

  void dispose() {
    controller?.dispose();
    focusNode?.dispose();
  }
}

class WriteArticleScreen extends StatefulWidget {
  const WriteArticleScreen({super.key});

  @override
  State<WriteArticleScreen> createState() => _WriteArticleScreenState();
}

class _WriteArticleScreenState extends State<WriteArticleScreen> {
  final TextEditingController _titleController = TextEditingController();
  List<ArticleBlock> _blocks = [];
  int _focusedBlockIndex = 0;
  bool _isSubmitting = false;
  Uint8List? _mediaBytes;
  String? _mediaExtension;
  String _uploadStep = '';
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _blocks = [ArticleBlock(type: 'text', content: '')];
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (var block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _formatText(String prefix, String suffix) {
    if (_blocks[_focusedBlockIndex].type != 'text') return;
    
    final controller = _blocks[_focusedBlockIndex].controller!;
    final text = controller.text;
    final selection = controller.selection;
    
    if (selection.start == -1) return;

    final selectedText = text.substring(selection.start, selection.end);
    
    if (selectedText.startsWith(prefix) && selectedText.endsWith(suffix)) {
      final unformattedText = selectedText.substring(prefix.length, selectedText.length - suffix.length);
      final newText = text.replaceRange(selection.start, selection.end, unformattedText);
      controller.value = TextEditingValue(
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
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + prefix.length + selectedText.length + suffix.length,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        setState(() {
          _isSubmitting = true;
          _uploadStep = 'Uploading image...';
        });

        final result = await MediaUploadService.uploadPostMedia(
          postId: 'inline_${DateTime.now().millisecondsSinceEpoch}',
          data: await image.readAsBytes(),
          fileExtension: 'jpg',
          mediaType: 'image',
        );

        if (result != null && result['url'] != null) {
          final url = result['url'] as String;
          
          setState(() {
            final activeBlock = _blocks[_focusedBlockIndex];
            final text = activeBlock.controller!.text;
            final selection = activeBlock.controller!.selection;
            
            String textBefore = '';
            String textAfter = '';

            if (selection.start != -1) {
              textBefore = text.substring(0, selection.start).trim();
              textAfter = text.substring(selection.end).trim();
            } else {
              textBefore = text.trim();
            }

            // Update current block with text before cursor
            activeBlock.controller!.text = textBefore;
            
            // Insert image block
            final imageBlock = ArticleBlock(type: 'image', content: url);
            
            // Insert new text block with text after cursor
            final newTextBlock = ArticleBlock(type: 'text', content: textAfter);
            
            _blocks.insert(_focusedBlockIndex + 1, imageBlock);
            _blocks.insert(_focusedBlockIndex + 2, newTextBlock);
            
            _focusedBlockIndex += 2;
          });
          
          Future.delayed(const Duration(milliseconds: 100), () {
            _blocks[_focusedBlockIndex].focusNode?.requestFocus();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image inserted!')),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Image pick error: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  // Allow picking PDF/Word for articles
  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        if (file.size > 10 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document is too large. Maximum 10MB.')),
          );
          return;
        }
        setState(() {
          _mediaBytes = file.bytes;
          _mediaExtension = file.extension ?? 'pdf';
        });

        // Trigger auto-extraction
        _autoExtractText(file.bytes!, file.extension ?? 'pdf');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Document pick error: $e');
    }
  }

  Future<void> _submit() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final title = _titleController.text.trim();
    // Concatenate all blocks into markdown
    StringBuffer contentBuffer = StringBuffer();
    for (var block in _blocks) {
      if (block.type == 'text') {
        contentBuffer.write(block.controller!.text);
      } else if (block.type == 'image') {
        contentBuffer.write('\n\n![image](${block.content})\n\n');
      }
    }
    final content = contentBuffer.toString().trim();

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

    setState(() {
      _isSubmitting = true;
      _uploadStep = 'Preparing...';
      _uploadProgress = 0.0;
    });

    try {
      Position? position;
      try {
        setState(() {
          _uploadStep = 'Detecting location...';
          _uploadProgress = 0.1;
        });
        position = await Geolocator.getCurrentPosition()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('Location detection failed (optional): $e');
      }

      Map<String, dynamic>? uploadResult;
      if (_mediaBytes != null) {
        setState(() {
          _uploadStep = 'Uploading document...';
          _uploadProgress = 0.3;
        });
        uploadResult = await MediaUploadService.uploadPostMedia(
          postId: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
          data: _mediaBytes!,
          fileExtension: _mediaExtension ?? 'pdf',
          mediaType: 'document',
        );
        setState(() => _uploadProgress = 0.7);
      }

      final mediaUrl = uploadResult?['url'] as String?;

      setState(() {
        _uploadStep = 'Publishing article...';
        _uploadProgress = 0.85;
      });

      final post = await PostService.createPost(
        title: title,
        body: content,
        category: 'Article',
        mediaUrl: mediaUrl,
        mediaType: mediaUrl != null ? 'document' : 'none',
        city: LocationService.getLocationString(),
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      if (!mounted) return;
      setState(() => _uploadProgress = 1.0);
      FeedEventBus.emit(FeedEvent(
FeedEventType.postCreated, post));
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Article posted successfully!')),
      );
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

  Future<void> _autoExtractText(Uint8List bytes, String ext) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    setState(() {
      _isSubmitting = true;
      _uploadStep = 'Reading document...';
    });

    try {
      final result = await MediaUploadService.uploadPostMedia(
        postId: 'extract_${DateTime.now().millisecondsSinceEpoch}',
        data: bytes,
        fileExtension: ext,
        mediaType: 'document',
      );

      if (result != null && result['extractedText'] != null) {
        final text = result['extractedText'] as String;
          if (text.trim().isNotEmpty) {
            setState(() {
              final activeBlock = _blocks[_focusedBlockIndex];
              if (activeBlock.type == 'text') {
                activeBlock.controller!.text = '${activeBlock.controller!.text}\n\n$text'.trim();
              } else {
                _blocks.add(ArticleBlock(type: 'text', content: text));
                _focusedBlockIndex = _blocks.length - 1;
              }
              _mediaBytes = null; // Clear attachment after extraction
              _mediaExtension = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Text extracted and added to article!')),
            );
          }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Auto-extract error: $e');
    } finally {
      setState(() => _isSubmitting = false);
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
                      maxLength: 2000,
                      style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                      fontFamily: 'serif', 
                      height: 1.1,
                      letterSpacing: -1.0,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'What is your article about?',
                      hintStyle: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w800),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 20),


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
                          _ToolbarIcon(
                            icon: Icons.image_outlined,
                            onTap: _isSubmitting ? () {} : _pickImage,
                          ),
                          _ToolbarIcon(
                            icon: Icons.description_outlined,
                            label: 'Doc',
                            onTap: _isSubmitting ? () {} : _pickDocument,
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

                  // --- DOCUMENT PREVIEW ---
                  if (_mediaBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.description, color: Color(0xFF006D6D)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Attached: ${_mediaExtension?.toUpperCase()}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.red),
                              onPressed: () => setState(() {
                                _mediaBytes = null;
                                _mediaExtension = null;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // --- EDITOR AREA (BLOCK-BASED) ---
                  Column(
                    children: List.generate(_blocks.length, (index) => _buildBlock(index)),
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

  Widget _buildBlock(int index) {
    final block = _blocks[index];
    if (block.type == 'text') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: TextField(
          controller: block.controller,
          focusNode: block.focusNode,
          maxLines: null,
          maxLength: 2000,
          keyboardType: TextInputType.multiline,
          onTap: () => setState(() => _focusedBlockIndex = index),
          style: const TextStyle(
            fontSize: 18,
            height: 1.8,
            color: Color(0xFF334155),
            fontFamily: 'Georgia',
          ),
          decoration: InputDecoration(
            hintText: index == 0 ? 'Share your knowledge...' : '',
            hintStyle: const TextStyle(color: Color(0xFFCBD5E0)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ProxyHelper.getUrl(block.content),
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white),
                  onPressed: () => setState(() {
                    _blocks.removeAt(index);
                    if (_focusedBlockIndex >= _blocks.length) {
                      _focusedBlockIndex = _blocks.length - 1;
                    }
                  }),
                ),
              ),
            ),
          ],
        ),
      );
    }
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
