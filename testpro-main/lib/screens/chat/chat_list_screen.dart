import 'package:flutter/material.dart';
import '../../services/backend_service.dart';
import '../../services/chat_service.dart';
import '../../models/chat_message.dart';
import 'chat_screen.dart';
import '../../config/app_theme.dart';
import 'package:intl/intl.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isLoading = true;
  List<dynamic> _chats = [];

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    final response = await BackendService.getChats();
    if (mounted) {
      setState(() {
        if (response.success) {
          _chats = response.data ?? [];
        }
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime date;
    if (timestamp is Map && timestamp['_seconds'] != null) {
      date = DateTime.fromMillisecondsSinceEpoch(timestamp['_seconds'] * 1000);
    } else {
      date = DateTime.tryParse(timestamp.toString()) ?? DateTime.now();
    }
    return DateFormat.jm().format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.builder(
                    itemCount: _chats.length,
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      final participants = (chat['participants'] as List).cast<String>();
                      final targetId = participants.firstWhere((id) => id != BackendService.instance.currentUserId, orElse: () => '');
                      final info = chat['participantInfo']?[targetId] ?? {};
                      final unread = chat['unreadCounts']?[BackendService.instance.currentUserId] ?? 0;

                      return ListTile(
                        onTap: () async {
                          // Mark as read and navigate
                          BackendService.markChatAsRead(chat['id']);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                id: chat['id'],
                                title: info['displayName'] ?? 'Chat',
                                isDirect: true,
                              ),
                            ),
                          );
                          _loadChats(); // Refresh unread count on return
                        },
                        leading: CircleAvatar(
                          backgroundImage: info['photoURL'] != null && info['photoURL'].isNotEmpty
                              ? NetworkImage(info['photoURL'])
                              : null,
                          child: info['photoURL'] == null || info['photoURL'].isEmpty ? const Icon(Icons.person) : null,
                        ),
                        title: Text(
                          info['displayName'] ?? 'User',
                          style: TextStyle(
                            fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          chat['lastMessage'] ?? 'No messages yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? Colors.black87 : Colors.grey,
                            fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimestamp(chat['lastTimestamp']),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            if (unread > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  unread.toString(),
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No messages yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}
