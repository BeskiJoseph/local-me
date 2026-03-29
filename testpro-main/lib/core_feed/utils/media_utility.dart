import 'package:flutter/foundation.dart';

class MediaUtility {
  /// The fixed URL of your Cloudflare Media Proxy
  static const String proxyBaseUrl = 'https://media-proxy.beskijosphjr.workers.dev';

  /// Sanitizes a URL to ensure it works in Flutter Web (CORS/429 bypass)
  static String getProxyUrl(String originalUrl) {
    if (originalUrl.isEmpty) return originalUrl;

    // 1. Check if it's a Google Avatar URL (The most common 429 source)
    if (originalUrl.contains('lh3.googleusercontent.com')) {
       // Extract the path after the domain
       final uri = Uri.parse(originalUrl);
       // Our worker is configured to handle /lh3/...
       return '$proxyBaseUrl/lh3${uri.path}${uri.query.isNotEmpty ? "?${uri.query}" : ""}';
    }

    // 2. Fallback: Return original 
    // (Post images are already proxied by the backend config)
    return originalUrl;
  }
}
