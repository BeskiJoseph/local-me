import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/post.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'package:intl/intl.dart';
import '../shared/widgets/user_avatar.dart';
import '../utils/safe_error.dart';

class GroupChatScreen extends StatefulWidget {
  final Post event;

  const GroupChatScreen({super.key, required this.event});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final Stream<List<ChatMessage>> _messagesStream;
  
  // Optimistic messages - shown immediately before backend confirms
  final List<ChatMessage> _pendingMessages = [];
  final Set<String> _sendingMessageIds = {};
  final Set<String> _confirmedMessageIds = {};

  bool get _canSend => _messageController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
    _messagesStream = ChatService.messagesStream(widget.event.id);
    Future.microtask(() => _messageFocus.requestFocus());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage({ChatMessage? retryMessage}) async {
    final user = AuthService.currentUser;
    if (user == null || (!_canSend && retryMessage == null)) return;

    ChatMessage optimisticMessage;
    String tempId;

    if (retryMessage != null) {
      optimisticMessage = retryMessage;
      tempId = retryMessage.id;
      if (!_pendingMessages.any((m) => m.id == tempId)) {
        setState(() {
          _pendingMessages.add(optimisticMessage);
        });
      }
    } else {
      final text = _messageController.text.trim();
      _messageController.clear();

      // Create optimistic message with temporary ID
      tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      optimisticMessage = ChatMessage(
        id: tempId,
        senderId: user.uid,
        senderName: user.displayName ?? 'User',
        senderProfileImage: user.photoURL,
        text: text,
        timestamp: DateTime.now(),
      );

      // Show immediately (optimistic UI)
      setState(() {
        _pendingMessages.add(optimisticMessage);
      });
    }

    setState(() {
      _sendingMessageIds.add(tempId);
    });
    
    HapticFeedback.lightImpact();
    // Scroll to bottom immediately
    _scrollToBottom();

    try {
      // Send to backend
      await ChatService.sendChatMessage(widget.event.id, optimisticMessage);
      
      // Mark as confirmed - but DON'T remove from pending yet
      // We'll keep showing it until the stream actually contains it
      if (mounted) {
        setState(() {
          _sendingMessageIds.remove(tempId);
          _confirmedMessageIds.add(tempId);
        });
      }
    } catch (e) {
      // Show error but keep message in UI (user can retry)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeErrorMessage(e)),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                _sendMessage(retryMessage: optimisticMessage);
              },
            ),
          ),
        );
        setState(() {
          _sendingMessageIds.remove(tempId);
        });
      }
    }
  }
  
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Inter',
              ),
            ),
            Text(
              'Event Group Chat',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && 
                    _pendingMessages.isEmpty && 
                    snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final serverMessages = snapshot.data ?? [];
                
                // Find server messages that match our pending messages (by content + sender + time)
                final Set<String> matchedPendingIds = {};
                for (final pending in _pendingMessages) {
                  // Look for matching server message (same sender, text, and close timestamp)
                  // Check ALL pending messages, not just confirmed ones
                  final match = serverMessages.any((server) => 
                    server.senderId == pending.senderId &&
                    server.text == pending.text &&
                    server.timestamp.difference(pending.timestamp).inSeconds.abs() < 60
                  );
                  if (match) {
                    matchedPendingIds.add(pending.id);
                  }
                }
                
                // Schedule cleanup of matched messages after build completes
                if (matchedPendingIds.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _pendingMessages.removeWhere((m) => matchedPendingIds.contains(m.id));
                        _confirmedMessageIds.removeWhere((id) => matchedPendingIds.contains(id));
                        _sendingMessageIds.removeWhere((id) => matchedPendingIds.contains(id));
                      });
                    }
                  });
                }
                
                // Remove matched pending messages from this build (they exist in server now)
                final pendingToShow = _pendingMessages.where((m) => 
                  !matchedPendingIds.contains(m.id)
                ).toList();
                
                final allMessages = [...pendingToShow, ...serverMessages];
                // Sort by timestamp (newest first for reverse list)
                allMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                if (allMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "Start the conversation",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade400, fontFamily: 'Inter'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Send the first message.",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontFamily: 'Inter'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: allMessages.length,
                  itemBuilder: (context, index) {
                    final message = allMessages[index];
                    final isMe = message.senderId == user?.uid;
                    final isPending = _sendingMessageIds.contains(message.id);

                    if (index == 0 && !isMe && !isPending) {
                      // Call safe scroll if we are very close to bottom and new message arrives
                      if (_scrollController.hasClients && _scrollController.offset < 50) {
                        _scrollToBottom();
                      }
                    }

                    return _buildMessageBubble(message, isMe, isPending: isPending);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe, {bool isPending = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                UserAvatar(
                  imageUrl: message.senderProfileImage,
                  name: message.senderName,
                  radius: 14,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe 
                        ? (isPending ? const Color(0xFF00B87C).withValues(alpha: 0.7) : const Color(0xFF00B87C))
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 14,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      if (isPending && isMe) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('h:mm a').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
                if (isPending && isMe) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.schedule, size: 10, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Text(
                    'sending',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocus,
                  maxLength: 1000,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(fontSize: 14),
                    counterText: '',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _canSend ? () => _sendMessage() : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _canSend ? const Color(0xFF00B87C) : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
