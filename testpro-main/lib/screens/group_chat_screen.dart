import 'package:flutter/material.dart';
import '../models/post.dart';
import 'chat/chat_screen.dart';

/// Legacy wrapper for [ChatScreen] to maintain backward compatibility for Event Group chats.
class GroupChatScreen extends StatelessWidget {
  final Post event;

  const GroupChatScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      id: event.id,
      title: event.title,
      isDirect: false,
    );
  }
}
