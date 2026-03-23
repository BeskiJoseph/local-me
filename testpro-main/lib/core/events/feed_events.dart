import 'dart:async';
import 'package:flutter/foundation.dart';

enum FeedEventType {
  postCreated,
  postDeleted,
  postUpdated,
  postLiked,
  commentAdded,
  userFollowed,
  eventMembershipChanged,
}

class FeedEvent {
  final FeedEventType type;
  final dynamic data;
  FeedEvent(this.type, this.data);
}

class FeedEventBus {
  static final _controller = StreamController<FeedEvent>.broadcast();
  static Stream<FeedEvent> get events => _controller.stream;

  static void emit(FeedEvent event) {
    if (kDebugMode) debugPrint('📡 EventBus emitting: ${event.type}');
    _controller.add(event);
  }
}
