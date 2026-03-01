import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'backend_service.dart';
import 'post_service.dart';
import 'media_upload_service.dart';

class SocketService {
  static IO.Socket? _socket;
  static final _roomController = StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get updates => _roomController.stream;

  static void init() {
    if (_socket != null) return;

    final String baseUrl = MediaUploadService.baseUrl;
    debugPrint('🔌 Initializing Socket.IO at $baseUrl');

    _socket = IO.io(baseUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .enableAutoConnect()
      .setReconnectionDelay(5000)
      .build());

    _socket!.onConnect((_) {
      debugPrint('🔌 Connected to WebSocket');
    });

    _socket!.onDisconnect((_) {
      debugPrint('🔌 Disconnected from WebSocket');
    });

    _socket!.on('like_update', (data) {
      debugPrint('📢 Real-time like update: $data');
      // Emit to global PostService event bus so all cards can update
      PostService.emit(FeedEvent(
        FeedEventType.postLiked,
        {
          'postId': data['postId'],
          'likeCount': data['likeCount'],
          'isLiked': null, // We don't change the current user's liked status via socket
        }
      ));
      _roomController.add(Map<String, dynamic>.from(data));
    });
  }

  static void joinPost(String postId) {
    if (_socket == null) init();
    _socket!.emit('join_post', postId);
    debugPrint('🏠 Joined room: post_$postId');
  }

  static void leavePost(String postId) {
    if (_socket != null) {
      _socket!.emit('leave_post', postId);
      debugPrint('🚶 Left room: post_$postId');
    }
  }

  static void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
