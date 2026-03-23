import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/chat_message.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/socket_service.dart';
import '../../config/app_theme.dart';
import 'package:intl/intl.dart';
import '../../services/backend_service.dart';
import '../../shared/widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String id;
  final String title;
  final bool isDirect;

  const ChatScreen({
    super.key, 
    required this.id, 
    required this.title, 
    this.isDirect = false
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final Stream<List<ChatMessage>> _messagesStream;
  StreamSubscription? _typingSubscription;
  
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;

  // Optimistic messages
  final List<ChatMessage> _pendingMessages = [];
  final Set<String> _sendingMessageIds = {};

  bool get _canSend => _messageController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _messagesStream = ChatService.messagesStream(widget.id, isDirect: widget.isDirect);
    
    // Reset unread count on entry
    if (widget.isDirect) {
      BackendService.markChatAsRead(widget.id);
    }
    
    // Join Socket Room
    if (widget.isDirect) {
      SocketService.joinChat(widget.id);
      _typingSubscription = SocketService.typingUpdates.listen((data) {
        if (data['chatId'] == widget.id && data['userId'] != AuthService.currentUser?.uid) {
          setState(() {
            _isOtherUserTyping = data['typing'] ?? false;
          });
        }
      });
    } else {
      SocketService.joinPost(widget.id);
    }
  }

  void _onTextChanged() {
    setState(() {});
    if (widget.isDirect) {
      ChatService.startTyping(widget.id);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        ChatService.stopTyping(widget.id);
      });
    }
  }

  @override
  void dispose() {
    if (widget.isDirect) {
      SocketService.leaveChat(widget.id);
      ChatService.stopTyping(widget.id);
    } else {
      SocketService.leavePost(widget.id);
    }
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final user = AuthService.currentUser;
    if (user == null || !_canSend) return;

    final text = _messageController.text.trim();
    _messageController.clear();
    ChatService.stopTyping(widget.id);

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = ChatMessage(
      id: tempId,
      senderId: user.uid,
      senderName: user.displayName ?? 'Me',
      senderProfileImage: user.photoURL,
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _pendingMessages.add(optimisticMessage);
      _sendingMessageIds.add(tempId);
    });
    
    HapticFeedback.lightImpact();
    _scrollToBottom();

    try {
      await ChatService.sendChatMessage(widget.id, optimisticMessage, isDirect: widget.isDirect);
      if (mounted) {
        setState(() {
          _sendingMessageIds.remove(tempId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sendingMessageIds.remove(tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }
  
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            if (_isOtherUserTyping)
              const Text('typing...', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500))
            else
              Text(widget.isDirect ? 'Direct Message' : 'Event Group', 
                   style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                final serverMessages = snapshot.data ?? [];
                
                // Matching logic
                final matchedIds = <String>{};
                for (var pending in _pendingMessages) {
                  if (serverMessages.any((s) => s.senderId == pending.senderId && s.text == pending.text)) {
                    matchedIds.add(pending.id);
                  }
                }
                
                if (matchedIds.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() => _pendingMessages.removeWhere((m) => matchedIds.contains(m.id)));
                  });
                }

                final displayMessages = [..._pendingMessages, ...serverMessages];
                displayMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: displayMessages.length,
                  itemBuilder: (context, index) {
                    final msg = displayMessages[index];
                    final isMe = msg.senderId == user?.uid;
                    return _buildMessageBubble(msg, isMe, isPending: _sendingMessageIds.contains(msg.id));
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
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) ...[
                UserAvatar(imageUrl: message.senderProfileImage, name: message.senderName, radius: 14),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(DateFormat('h:mm a').format(message.timestamp), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocus,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _canSend ? _sendMessage : null,
              icon: Icon(Icons.send, color: _canSend ? AppTheme.primary : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
