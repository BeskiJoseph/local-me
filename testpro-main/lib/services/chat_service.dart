import '../models/chat_message.dart';
import 'backend_service.dart';

class ChatService {
  // Note: Streams are difficult to replace with JSON REST.
  // Converting to a periodic poll or simple retrieval for now.
  static Stream<List<ChatMessage>> messagesStream(String eventId) {
    return Stream.periodic(const Duration(seconds: 15))
        .asyncMap((_) => BackendService.getMessages(eventId))
        .map((response) {
          if (!response.success || response.data == null) return <ChatMessage>[];
          return response.data!.map<ChatMessage>((json) => ChatMessage.fromJson(json)).toList();
        });
  }

  static Future<void> sendChatMessage(String eventId, ChatMessage message) async {
    final response = await BackendService.sendChatMessage(eventId, message.text);
    if (!response.success) throw response.error ?? "Failed to send message via backend";
  }
}
