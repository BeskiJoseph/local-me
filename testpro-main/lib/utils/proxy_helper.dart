import 'package:flutter/foundation.dart';
import '../services/media_upload_service.dart';

class ProxyHelper {
  /// Rewrites a URL to go through our backend proxy if needed.
  /// 
  /// On Android, R2 SSL certificates are often untrusted by emulators/older devices.
  /// We solve this by "tunneling" the image through our trusted backend.
  static String getUrl(String originalUrl) {
    if (originalUrl.isEmpty) return '';

    // Production recommendation: use a proper public R2 domain with valid TLS
    // so you can return originalUrl directly.
    
    // FORCE PROXY for R2 Worker on Web to avoid CORS (statusCode: 0)
    // and for Google Profile images which can sometimes have CORS issues or 429s on web
    bool forceProxy = kIsWeb && (originalUrl.contains('workers.dev') || originalUrl.contains('googleusercontent.com'));

    // If you still need to proxy media (debug/emulator TLS issues), enable it via:
    // --dart-define=USE_MEDIA_PROXY=true
    const bool useProxyEnv = bool.fromEnvironment('USE_MEDIA_PROXY', defaultValue: false);
    
    if (!forceProxy && !useProxyEnv) return originalUrl;

    // Removed debug print to reduce console spam
    // Images are now cached with CachedNetworkImage

    final encoded = Uri.encodeComponent(originalUrl);
    return '${MediaUploadService.baseUrl}/api/proxy?url=$encoded';
  }
}
