import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import '../models/post.dart'; // Just in case, though not used in method signatures here

class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<ChatMessage>> messagesStream(String eventId) {
    return _db.collection('posts')
        .doc(eventId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .toList());
  }

  static Future<void> sendChatMessage(String eventId, ChatMessage message) async {
    await _db.collection('posts')
        .doc(eventId)
        .collection('messages')
        .add(message.toMap());
  }
}
