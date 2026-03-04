import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';

class ChatService {
  // Local memory cache for instant UI rendering across chat opens
  static final Map<String, List<ChatMessage>> _messagesCache = {};
  
  static void _updateCache(String eventId, List<ChatMessage> messages) {
    if (_messagesCache.length > 20) {
      // Remove oldest entry
      _messagesCache.remove(_messagesCache.keys.first);
    }
    _messagesCache[eventId] = messages;
  }

  /// Yields messages instantly from memory cache, then establishes a
  /// real-time Firestore listener (snapshots) for instant updates.
  static Stream<List<ChatMessage>> messagesStream(String eventId) {
    // Use a StreamController so we can push cache instantly AND stream Firestore
    final controller = StreamController<List<ChatMessage>>();

    // 1. Push cache IMMEDIATELY (synchronous, before any async gap)
    if (_messagesCache.containsKey(eventId)) {
      controller.add(_messagesCache[eventId]!);
    }

    // 2. Start Firestore real-time listener
    final subscription = FirebaseFirestore.instance
        .collection('posts')
        .doc(eventId)
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

          _updateCache(eventId, messages);
          controller.add(messages);
        }, onError: (e) => controller.addError(e));

    // 3. Clean up Firestore listener when stream is cancelled (user leaves screen)
    controller.onCancel = () => subscription.cancel();

    return controller.stream;
  }

  static Future<void> sendChatMessage(String eventId, ChatMessage message) async {
    // Write directly to Firestore using the native SDK.
    // This allows the native Firestore cache to immediately reflect the sent message locally, 
    // replacing the need for fragile memory-level optimistic state when navigating between screens.
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(eventId)
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
