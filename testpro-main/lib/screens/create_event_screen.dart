import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/media_upload_service.dart';
import '../services/post_service.dart';
import '../services/backend_service.dart';
import '../models/post.dart';
import 'package:geolocator/geolocator.dart';
import 'group_chat_screen.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();
  
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _coverImage;
  bool _isSubmitting = false;
  
  DateTime? _selectedStartDate;
  TimeOfDay? _selectedStartTime;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedEndTime;

  @override
  void dispose() {
    _titleController.dispose();
    _startDateController.dispose();
    _startTimeController.dispose();
    _endDateController.dispose();
    _endTimeController.dispose();
    _locationController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _coverImage = File(image.path);
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? DateTime.now() : (_selectedStartDate ?? DateTime.now()),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _selectedStartDate = picked;
          _startDateController.text = "${picked.month}/${picked.day}/${picked.year}";
          // Reset end date if it's now before the start date
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) {
            _selectedEndDate = null;
            _endDateController.clear();
          }
        } else {
          _selectedEndDate = picked;
          _endDateController.text = "${picked.month}/${picked.day}/${picked.year}";
        }
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _selectedStartTime = picked;
          _startTimeController.text = picked.format(context);
        } else {
          _selectedEndTime = picked;
          _endTimeController.text = picked.format(context);
        }
      });
    }
  }

  Future<void> _submit() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an event title')),
      );
      return;
    }

    if (_selectedStartDate == null || _selectedStartTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Start Date and Time')),
      );
      return;
    }

    if (_selectedEndDate == null || _selectedEndTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an End Date and Time')),
      );
      return;
    }

    // Combine date and time for validation and payload
    final DateTime startDateTime = DateTime(
      _selectedStartDate!.year, _selectedStartDate!.month, _selectedStartDate!.day,
      _selectedStartTime!.hour, _selectedStartTime!.minute,
    );

    final DateTime endDateTime = DateTime(
      _selectedEndDate!.year, _selectedEndDate!.month, _selectedEndDate!.day,
      _selectedEndTime!.hour, _selectedEndTime!.minute,
    );

    if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after the start time')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('Location detection failed (optional): $e');
      }
      
      String? coverImageUrl;
      if (_coverImage != null) {
        coverImageUrl = await MediaUploadService.uploadPostMedia(
          postId: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
          data: await _coverImage!.readAsBytes(),
          fileExtension: 'jpg',
          mediaType: 'image',
        );
      }

      final createdEventId = await PostService.createEvent(
        title: _titleController.text.trim(),
        description: '', // Can be improved if we add a description field
        eventType: 'Classic',
        eventStartDate: startDateTime,
        eventEndDate: endDateTime,
        location: _locationController.text.trim(),
        latitude: position?.latitude,
        longitude: position?.longitude,
        city: 'Agastiswaram',
        country: 'India',
        mediaUrl: coverImageUrl,
        isFree: true,
      );

      if (!mounted) return;

      final createdPostResp = await BackendService.getPost(createdEventId);
      if (!mounted) return;

      if (createdPostResp.success && createdPostResp.data != null) {
        final post = Post.fromJson(createdPostResp.data!);
        PostService.emit(FeedEvent(FeedEventType.postCreated, post));
        
        if (!mounted) return;
        // Navigate to the newly created group chat
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => GroupChatScreen(event: post)),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating event: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F2937), size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Create Event',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D6D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Event Title (Heading) ---
                  const Text(
                    'Event Title',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4A5D7E),
                      fontFamily: 'serif',
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildSlimInput(controller: _titleController, hintText: 'Event Title'),
                  
                  const SizedBox(height: 32),

                  // --- Event Description (Subheading) ---
                  const Text(
                    'Event Description (optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // --- Cover Image Box ---
                  Container(
                    width: double.infinity,
                    height: 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFBFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                    ),
                    child: _coverImage != null 
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_coverImage!, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => setState(() => _coverImage = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: _buildActionPill(
                                icon: Icons.camera_alt,
                                label: 'Change',
                                onTap: _pickImage,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt_rounded, size: 48, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 16),
                            _buildActionPill(
                              icon: Icons.camera_alt,
                              label: 'Add Cover Image',
                              onTap: _pickImage,
                            ),
                          ],
                        ),
                  ),
                  
                  const SizedBox(height: 32),

                  // --- Start Date & Time ---
                  _buildSectionLabel(icon: Icons.play_circle_fill_rounded, title: 'Starts', hasArrow: false),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSlimInput(
                          controller: _startDateController, 
                          hintText: 'Date', 
                          isReadOnly: true,
                          prefixIcon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isStart: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSlimInput(
                          controller: _startTimeController, 
                          hintText: 'Time', 
                          isReadOnly: true,
                          prefixIcon: Icons.access_time_outlined,
                          onTap: () => _pickTime(isStart: true),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),

                  // --- End Date & Time ---
                  _buildSectionLabel(icon: Icons.stop_circle_rounded, title: 'Ends', hasArrow: false),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSlimInput(
                          controller: _endDateController, 
                          hintText: 'Date', 
                          isReadOnly: true,
                          prefixIcon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isStart: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSlimInput(
                          controller: _endTimeController, 
                          hintText: 'Time', 
                          isReadOnly: true,
                          prefixIcon: Icons.access_time_outlined,
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),

                  // --- Location ---
                  _buildSectionLabel(icon: Icons.location_on_rounded, title: 'Location'),
                  _buildSlimInput(
                    controller: _locationController, 
                    hintText: 'Enter Location',
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  
                  const SizedBox(height: 24),

                  // --- Tags ---
                  _buildSectionLabel(icon: Icons.local_offer_rounded, title: 'Tags (optional)'),
                  _buildSlimInput(controller: _tagsController, hintText: 'Add tags, separated by commas'),
                  
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({required IconData icon, required String title, bool hasArrow = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF475569)),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
              fontFamily: 'Inter',
            ),
          ),
          if (hasArrow) ...[
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFCBD5E0)),
          ]
        ],
      ),
    );
  }

  Widget _buildSlimInput({
    required TextEditingController controller,
    required String hintText,
    bool isReadOnly = false,
    IconData? prefixIcon,
    VoidCallback? onTap,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        readOnly: isReadOnly,
        onTap: onTap,
        style: const TextStyle(fontSize: 15, color: Color(0xFF334155), fontFamily: 'Inter'),
        decoration: InputDecoration(
          hintText: hintText,
          // CRITICAL: Prevent double borders by overriding global theme
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          fillColor: Colors.transparent,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintStyle: const TextStyle(fontSize: 15, color: Color(0xFFCBD5E0), fontFamily: 'Inter'),
          prefixIcon: prefixIcon != null 
              ? Icon(prefixIcon, color: const Color(0xFFCBD5E0), size: 18) 
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
        ),
      ),
    );
  }

  Widget _buildActionPill({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF006D6D)),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
