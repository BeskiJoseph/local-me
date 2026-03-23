import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'media_upload_service.dart';
import '../core/events/feed_events.dart';

class SocketService {
  static IO.Socket? _socket;
  static final _roomController = StreamController<Map<String, dynamic>>.broadcast();
  static final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  static final Set<String> _currentRooms = {}; // Track active rooms for re-join on reconnect

  static Stream<Map<String, dynamic>> get updates => _roomController.stream;
  static Stream<Map<String, dynamic>> get typingUpdates => _typingController.stream;

  static void init(String token) {
    if (_socket != null) {
      // If token changed, reconnect
      if (_socket!.io.options?['auth']?['token'] != token) {
        dispose();
      } else {
        return;
      }
    }

    final String baseUrl = MediaUploadService.baseUrl;
    debugPrint('🔌 Initializing Socket.IO at $baseUrl (Authenticated)');

    _socket = IO.io(baseUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .enableAutoConnect()
      .setReconnectionDelay(5000)
      .setAuth({'token': token})
      .build());

    _socket!.onConnect((_) {
      debugPrint('🔌 Connected to WebSocket');
    });

    _socket!.onDisconnect((_) {
      debugPrint('🔌 Disconnected from WebSocket');
    });

    _socket!.onReconnect((_) {
      debugPrint('🔌 Reconnected to WebSocket! Re-joining ${_currentRooms.length} rooms.');
      for (var room in _currentRooms) {
        _socket!.emit('join_room_direct', room); // Using a backend helper or raw emit
        // Or just map back to the specific events:
        if (room.startsWith('post_')) _socket!.emit('join_post', room.replaceFirst('post_', ''));
        if (room.startsWith('chat_')) _socket!.emit('join_chat', room.replaceFirst('chat_', ''));
      }
    });

    // --- Global Metadata Listeners ---
    _socket!.on('like_update', (data) {
      FeedEventBus.emit(FeedEvent(
        FeedEventType.postLiked,
        {
          'postId': data['postId'],
          'likeCount': data['likeCount'],
          'isLiked': null,
        }
      ));
      _roomController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('comment_update', (data) {
      FeedEventBus.emit(FeedEvent(
        FeedEventType.commentAdded,
        {
          'postId': data['postId'],
          'commentCount': data['commentCount'],
          'newComment': data['newComment'],
        }
      ));
      _roomController.add(Map<String, dynamic>.from(data));
    });

    // --- Chat Listeners ---
    _socket!.on('user_typing', (data) {
      _typingController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('error', (err) {
      debugPrint('🚨 Socket Error: $err');
    });
  }

  // --- Post Rooms ---
  static void joinPost(String postId) {
    final room = 'post_$postId';
    _currentRooms.add(room);
    _socket?.emit('join_post', postId);
  }

  static void leavePost(String postId) {
    _currentRooms.remove('post_$postId');
    _socket?.emit('leave_post', postId);
  }

  // --- Chat Rooms ---
  static void joinChat(String chatId) {
    final room = 'chat_$chatId';
    _currentRooms.add(room);
    _socket?.emit('join_chat', chatId);
  }

  static void leaveChat(String chatId) {
    _currentRooms.remove('chat_$chatId');
    _socket?.emit('leave_chat', chatId);
  }

  static void emitTypingStart(String chatId) {
    _socket?.emit('typing_start', chatId);
  }

  static void emitTypingStop(String chatId) {
    _socket?.emit('typing_stop', chatId);
  }

  static void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
