import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import 'backend_service.dart';
import 'socket_service.dart';

class ChatService {
  // Local memory cache for instant UI rendering across chat opens
  static final Map<String, List<ChatMessage>> _messagesCache = {};
  
  static void _updateCache(String id, List<ChatMessage> messages) {
    if (_messagesCache.length > 20) {
      _messagesCache.remove(_messagesCache.keys.first);
    }
    _messagesCache[id] = messages;
  }

  /// Yields messages instantly from memory cache, then establishes a
  /// real-time Firestore listener for both Event and DM chats.
  static Stream<List<ChatMessage>> messagesStream(String id, {bool isDirect = false}) {
    final controller = StreamController<List<ChatMessage>>.broadcast();

    if (_messagesCache.containsKey(id)) {
      controller.add(_messagesCache[id]!);
    }

    // Path selection: Events live under 'posts', DMs live under 'chats'
    final collectionPath = isDirect ? 'chats' : 'posts';
    
    final subscription = FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(id)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
          final messages = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            if (data['timestamp'] == null) {
              data['timestamp'] = DateTime.now().toIso8601String();
            } else if (data['timestamp'] is Timestamp) {
              data['timestamp'] = (data['timestamp'] as Timestamp).toDate().toIso8601String();
            }
            return ChatMessage.fromJson(data);
          }).toList();

          _updateCache(id, messages);
          controller.add(messages);
        }, onError: (e) => controller.addError(e));

    controller.onCancel = () => subscription.cancel();

    return controller.stream;
  }

  static Future<void> sendChatMessage(String id, ChatMessage message, {bool isDirect = false}) async {
    if (isDirect) {
      // For DMs, use the backend to handle metadata/unread transactions
      final response = await BackendService.sendChatMessage(
        chatId: id,
        text: message.text,
      );
      if (!response.success) {
        throw Exception(response.error ?? 'Failed to send message');
      }
    } else {
      // For legacy Event Chats, write directly to Firestore as before
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(id)
          .collection('messages')
          .add({
        'senderId': message.senderId,
        'senderName': message.senderName,
        'senderProfileImage': message.senderProfileImage,
        'text': message.text,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  // --- Real-time UX (Typing Indicators) ---

  static void startTyping(String id) {
    SocketService.emitTypingStart(id);
  }

  static void stopTyping(String id) {
    SocketService.emitTypingStop(id);
  }
}
