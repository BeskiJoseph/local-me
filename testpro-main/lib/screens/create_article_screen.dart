import 'package:flutter/material.dart';
import '../services/post_service.dart';
// import '../utils/document_parser.dart';
import '../config/app_theme.dart';
import '../utils/safe_error.dart';

class CreateArticleScreen extends StatefulWidget {
  const CreateArticleScreen({super.key});

  @override
  State<CreateArticleScreen> createState() => _CreateArticleScreenState();
}

class _CreateArticleScreenState extends State<CreateArticleScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();
  
  bool _isPublishing = false;
  bool _isImporting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _importDocument() async {
    // Note: DocumentParser is currently disabled as it was missing from the friend's zip.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document import is currently unavailable.')),
    );
  }

  Future<void> _publishArticle() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title for your article.')),
      );
      _titleFocus.requestFocus();
      return;
    }

    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Article body cannot be empty.')),
      );
      _bodyFocus.requestFocus();
      return;
    }

    setState(() => _isPublishing = true);

    try {
      await PostService.createPost(
        title: title,
        body: body,
        scope: 'global', // 'global' so everyone can see it in Artizone
        category: 'Article', // Key for filtering
        mediaType: 'none',
        // Optional: you could add cover image uploading here later
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Article published successfully!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: ${safeErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Write Article',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: AppTheme.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: _isPublishing ? null : _publishArticle,
            child: _isPublishing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Publish', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Toolbar for text styles and import
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _importDocument,
                    icon: _isImporting 
                       ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                       : const Icon(Icons.drive_folder_upload, size: 18),
                    label: const Text('Import Word / PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.format_bold),
                    onPressed: () {}, // Stylistic stub
                    tooltip: 'Bold',
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_italic),
                    onPressed: () {}, // Stylistic stub
                    tooltip: 'Italic',
                  ),
                ],
              ),
            ),
            
            // Editor Area
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: TextField(
                        controller: _titleController,
                        focusNode: _titleFocus,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          fontFamily: AppTheme.fontFamily,
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Article Title...',
                          hintStyle: TextStyle(color: Color(0xFFCCCCCC), fontSize: 28, fontWeight: FontWeight.w800),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                      child: TextField(
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: Color(0xFF333333),
                          fontFamily: AppTheme.fontFamily,
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Start writing your story...',
                          hintStyle: TextStyle(color: Color(0xFFCCCCCC), fontSize: 18),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
