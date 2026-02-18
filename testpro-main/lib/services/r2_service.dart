/// This file previously contained Cloudflare R2 access/secret keys and
/// direct client-side access to your R2 bucket, which is not acceptable
/// for a production app (anyone could extract the keys from the binary).
///
/// For production:
/// - Move all R2 operations to a secure backend (server/Cloudflare Worker/etc).
/// - Expose only signed URLs or a minimal proxy API to the Flutter client.
/// - Do NOT ship R2 access/secret keys in source control or in the app.
///
/// The class below is intentionally left as a stub so that any accidental
/// usage will clearly fail fast and remind you to wire up a backend instead.

class R2Service {
  R2Service._(); // Prevent instantiation

  static Never _throwUnimplemented() {
    throw StateError(
      'R2Service is not available on the client. '
      'Implement media uploads via a secure backend service '
      'and call that from your Flutter app instead.',
    );
  }

  static Future<String?> uploadProfileImage({
    required String userId,
    required List<int> data,
    String fileExtension = 'jpg',
  }) async {
    _throwUnimplemented();
  }

  static Future<String?> uploadPostMedia({
    required String postId,
    required List<int> data,
    String fileExtension = 'jpg',
    String mediaType = 'image',
  }) async {
    _throwUnimplemented();
  }
}
