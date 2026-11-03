import 'dart:convert';
import 'dart:typed_data';

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
    // Reuse a valid cached ID token. Firebase refreshes it automatically only when
    // it is expired; forcing a refresh on every request makes retries fail on
    // transient Identity Toolkit/network outages before reaching the Worker.
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
      final message = data['error']?.toString() ??
          'Backend request failed (${result.statusCode}).';
      final requestId = data['requestId']?.toString();
      final stage = data['stage']?.toString();
      final diagnostic = [
        if (stage != null && stage.isNotEmpty) 'stage=$stage',
        if (requestId != null && requestId.isNotEmpty) 'requestId=$requestId',
        'HTTP ${result.statusCode}',
      ].join(', ');
      throw Exception('$message ($diagnostic)');
    }
    return data;
  }

  Future<String> uploadMedia({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (bytes.isEmpty) throw StateError('The image is empty.');
    if (bytes.length > 8 * 1024 * 1024) {
      throw StateError('Images must be smaller than 8 MB.');
    }
    final data = await _post('/api/media/upload', {
      'path': path,
      'contentType': contentType,
      'data': base64Encode(bytes),
    });
    final url = data['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw StateError('The media service did not return an image URL.');
    }
    return url;
  }

  Future<Map<String, dynamic>> generatePostArtwork({
    required String postType,
    required String notes,
    required String contentLanguage,
  }) async {
    final data = await _post('/api/posts/generate-image', {
      'postType': postType,
      'notes': notes,
      'contentLanguage': contentLanguage,
    });
    final url = data['imageUrl']?.toString() ?? '';
    if (url.isEmpty) {
      throw StateError('The image generator did not return an artwork URL.');
    }
    return {
      'imageUrl': url,
      'localizedProfile': Map<String, dynamic>.from(
        data['localizedProfile'] as Map? ?? const {},
      ),
    };
  }

  Future<List<String>> generatePost(String postId) async {
    final requestId = 'post-${DateTime.now().microsecondsSinceEpoch}';
    final data = await _post('/api/posts/generate', {
      'postId': postId,
      'requestId': requestId,
    });
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

  Future<String> suggestPostFrame({
    required String postType,
    required String notes,
  }) async {
    final data = await _post('/api/posts/suggest-frame', {
      'postType': postType,
      'notes': notes,
    });
    return data['frameStyle']?.toString() ?? 'classic';
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

  Future<void> recordWhatsAppDelivery({
    required String postId,
    required String destination,
  }) async {
    await _post('/api/posts/whatsapp-delivery', {
      'postId': postId,
      'destination': destination,
      'confirmed': true,
    });
  }

  Future<void> saveSocialCredentials(Map<String, String> credentials) async {
    await _post('/api/social/credentials', credentials);
  }
}
