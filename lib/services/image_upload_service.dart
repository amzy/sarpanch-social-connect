import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'backend_api_service.dart';

class ImageUploadService {
  static const int maxBytes = 8 * 1024 * 1024;

  Future<String> uploadFile({
    required String uid,
    required String path,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('The selected image is empty.');
    final contentType = _contentType(file.name);
    return BackendApiService().uploadMedia(
      path: _key(uid, path),
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<String> uploadBytes({
    required String uid,
    required String path,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw Exception('The generated poster image is empty.');
    return BackendApiService().uploadMedia(
      path: _key(uid, path),
      bytes: bytes,
      contentType: 'image/png',
    );
  }

  String _key(String uid, String path) {
    final normalized = path
        .replaceAll('\\\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (normalized.isNotEmpty && normalized.first == 'users') {
      normalized.removeAt(0);
    }
    if (normalized.isNotEmpty && normalized.first == uid) {
      normalized.removeAt(0);
    }
    return '$uid/${normalized.join('/')}';
  }

  String _contentType(String name) {
    final extension = name.toLowerCase().split('.').last;
    switch (extension) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }
}
