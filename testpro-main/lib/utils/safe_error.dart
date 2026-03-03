/// Maps raw exceptions to safe, user-facing error messages.
///
/// SECURITY: Never expose raw backend errors, stack traces, or
/// validation logic to the UI. This function maps known error
/// patterns to safe messages and falls back to a generic one.
String safeErrorMessage(dynamic error, {String fallback = 'Something went wrong. Please try again.'}) {
  final raw = error.toString().toLowerCase();

  // ── Network / Connectivity ──
  if (raw.contains('socketexception') || raw.contains('handshakeexception')) {
    return 'Unable to connect. Please check your internet connection.';
  }
  if (raw.contains('timeout') || raw.contains('timed out')) {
    return 'Request timed out. Please try again.';
  }

  // ── Auth / Session ──
  if (raw.contains('user-not-found') || raw.contains('wrong-password')) {
    return 'Invalid email or password.';
  }
  if (raw.contains('email-already-in-use')) {
    return 'This email is already registered.';
  }
  if (raw.contains('weak-password')) {
    return 'Password is too weak. Use at least 6 characters.';
  }
  if (raw.contains('too-many-requests') || raw.contains('429')) {
    return 'Too many attempts. Please wait a moment.';
  }
  if (raw.contains('401') || raw.contains('unauthorized')) {
    return 'Session expired. Please sign in again.';
  }

  // ── Location ──
  if (raw.contains('location') && raw.contains('denied')) {
    return 'Location permission denied. Please enable it in settings.';
  }
  if (raw.contains('location') && raw.contains('disabled')) {
    return 'Location services are disabled. Please enable them.';
  }
  if (raw.contains('permanently denied')) {
    return 'Location access permanently denied. Enable in device settings.';
  }

  // ── OTP ──
  if (raw.contains('invalid') && raw.contains('otp')) {
    return 'Invalid verification code. Please try again.';
  }
  if (raw.contains('expired') && raw.contains('otp')) {
    return 'Verification code expired. Request a new one.';
  }

  // ── Server ──
  if (raw.contains('500') || raw.contains('internal server')) {
    return 'Server error. Please try again later.';
  }
  if (raw.contains('503') || raw.contains('service unavailable')) {
    return 'Service temporarily unavailable. Please try again shortly.';
  }

  // ── Fallback: strip "Exception:" prefix if present, but keep it safe ──
  final cleaned = error.toString().replaceAll(RegExp(r'^Exception:\s*'), '');
  // If cleaned message looks safe (short, no stack trace markers), use it
  if (cleaned.length < 100 && !cleaned.contains('\n') && !cleaned.contains('at ')) {
    return cleaned;
  }

  return fallback;
}
