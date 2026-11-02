import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Authenticated HTTP client for the Cloudflare Worker backend.
class BackendApiService {
  BackendApiService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const String _baseUrl = String.fromEnvironment(
    'BACKEND_API_URL',
    defaultValue: '',
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    if (_baseUrl.trim().isEmpty) {
      throw StateError(
        'Backend API is not configured. Build with --dart-define=BACKEND_API_URL=https://YOUR-WORKER.workers.dev',
      );
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError(
          'Your sign-in session has expired. Please sign in again.');
    }
    final uri = Uri.parse('${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
    final result = await http
        .post(
          uri,
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Preserve the HTTP status in the user-facing error below.
    }
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw Exception(data['error']?.toString() ??
          'Backend request failed (${result.statusCode}).');
    }
    return data;
  }

  Future<List<String>> generatePost(String postId) async {
    final data = await _post('/api/posts/generate', {'postId': postId});
    return (data['captions'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  Future<List<String>> moreCaptionOptions(String postId) async {
    final data = await _post('/api/posts/more-options', {'postId': postId});
    return (data['captions'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  Future<String> transliterateName(String text) async {
    final data = await _post('/api/profile/transliterate', {'text': text});
    return data['hindi']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> approveAndPublish({
    required String postId,
    required String caption,
  }) =>
      _post('/api/posts/approve-and-publish', {
        'postId': postId,
        'caption': caption,
      });

  Future<void> rejectPost(String postId) async {
    await _post('/api/posts/reject', {'postId': postId});
  }

  Future<Map<String, dynamic>> retryPost(String postId) =>
      _post('/api/posts/retry', {'postId': postId});

  Future<void> saveSocialCredentials(Map<String, String> credentials) async {
    await _post('/api/social/credentials', credentials);
  }
}
