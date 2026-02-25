import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'backend_service.dart';

class ChatService {
  /// Stream that emits immediately with current messages, then polls every 5 seconds
  /// Increased from 2s to reduce API calls while maintaining near-real-time feel
  static Stream<List<ChatMessage>> messagesStream(String eventId) async* {
    // Emit immediately on open
    yield await _fetchMessages(eventId);

    // Then poll every 5 seconds for near-real-time chat.
    // User's own messages appear instantly via optimistic UI.
    await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
      yield await _fetchMessages(eventId);
    }
  }

  static Future<List<ChatMessage>> _fetchMessages(String eventId) async {
    try {
      final response = await BackendService.getMessages(eventId);
      if (!response.success || response.data == null) return <ChatMessage>[];
      return response.data!
          .map<ChatMessage>((json) => ChatMessage.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Chat fetch error: $e');
      return <ChatMessage>[];
    }
  }

  static Future<void> sendChatMessage(String eventId, ChatMessage message) async {
    final response = await BackendService.sendChatMessage(eventId, message.text);
    if (!response.success) throw response.error ?? "Failed to send message via backend";
  }
}
