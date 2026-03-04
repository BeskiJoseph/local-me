import 'dart:async';

enum AuthEventType {
  authenticated,
  unauthenticated,
  sessionExpired,
}

class AuthEvent {
  final AuthEventType type;
  final String? message;

  AuthEvent(this.type, {this.message});
}

class AuthEventStream {
  static final StreamController<AuthEvent> _controller = StreamController<AuthEvent>.broadcast();

  static Stream<AuthEvent> get events => _controller.stream;

  static void emit(AuthEvent event) {
    _controller.add(event);
  }

  static void emitSessionExpired() {
    _controller.add(AuthEvent(AuthEventType.sessionExpired, message: 'Your session has expired. Please sign in again.'));
  }
}
