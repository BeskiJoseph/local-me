import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:testpro/services/backend_service.dart';

// Subclass to mock authentication logic
class TestBackendClient extends BackendClient {
  TestBackendClient({
    required http.Client client,
    String? baseUrl,
  }) : super(client: client, baseUrl: baseUrl);

  @override
  Future<String?> getIdToken() async {
    return 'test_token';
  }
}

void main() {
  group('BackendClient Tests', () {
    const testBaseUrl = 'http://test.api';

    test('toggleLike sends correct POST request with auth token', () async {
      final mockClient = MockClient((request) async {
        // Verify Request
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/api/interactions/like');
        expect(request.headers['Authorization'], 'Bearer test_token');
        expect(request.headers['Content-Type'], 'application/json');
        
        final body = jsonDecode(request.body);
        expect(body['postId'], 'post123');

        // Return successful response
        return http.Response(jsonEncode({'success': true}), 200);
      });

      final client = TestBackendClient(
        client: mockClient,
        baseUrl: testBaseUrl,
      );

      final result = await client.toggleLike('post123');
      expect(result, isTrue);
    });

    test('addComment sends correct POST request', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), '$testBaseUrl/api/interactions/comment');
        
        final body = jsonDecode(request.body);
        expect(body['postId'], 'post123');
        expect(body['text'], 'Hello World');

        return http.Response('OK', 200);
      });

      final client = TestBackendClient(client: mockClient, baseUrl: testBaseUrl);

      final result = await client.addComment('post123', 'Hello World');
      expect(result, isTrue);
    });

    test('handles error gracefully (returns false)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });

      final client = TestBackendClient(client: mockClient, baseUrl: testBaseUrl);

      final result = await client.toggleLike('post123');
      expect(result, isFalse);
    });
  });
}
