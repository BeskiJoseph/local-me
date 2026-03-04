/// Maps raw exceptions to safe, user-facing error messages.
///
/// SECURITY: Never expose raw backend errors, stack traces, or
/// validation logic to the UI. This function maps known error
/// patterns to safe messages and falls back to a generic one.
String safeErrorMessage(dynamic error, {String fallback = 'Something went wrong. Please try again.'}) {
  final msg = error.toString().toLowerCase();

  // ── User Recommended Mappings ──
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Network timeout. Please try again.';
  }
  if (msg.contains('socket') || msg.contains('connection failed')) {
    return 'No internet connection.';
  }
  if (msg.contains('401') || msg.contains('unauthorized')) {
    return 'Session expired. Please login again.';
  }

  // ── Existing Auth Mappings ──
  if (msg.contains('user-not-found') || msg.contains('wrong-password')) {
    return 'Invalid email or password.';
  }
  if (msg.contains('email-already-in-use')) {
    return 'This email is already registered.';
  }
  if (msg.contains('weak-password')) {
    return 'Password is too weak.';
  }
  if (msg.contains('too-many-requests') || msg.contains('429')) {
    return 'Too many attempts. Please wait a moment.';
  }

  // ── Existing Location Mappings ──
  if (msg.contains('location') && msg.contains('denied')) {
    return 'Location permission denied. Please enable it in settings.';
  }
  if (msg.contains('location') && msg.contains('disabled')) {
    return 'Location services are disabled.';
  }

  // ── Existing Server Mappings ──
  if (msg.contains('500') || msg.contains('internal server')) {
    return 'Server error. Please try again later.';
  }

  // Final safety check: if cleaned message looks safe (short, no stack trace markers), use it
  final cleaned = error.toString().replaceAll(RegExp(r'^Exception:\s*'), '');
  if (cleaned.length < 50 && !cleaned.contains('\n') && !cleaned.contains('at ')) {
    return cleaned;
  }

  return fallback;
}
