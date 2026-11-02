import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImageUploadService {
  static const int maxBytes = 1024 * 1024;

  Future<XFile> compress(XFile input) async {
    if (kIsWeb) {
      // Browser-picked files are already browser-managed. Do not request a
      // native temporary directory or pass a blob URL to a native compressor.
      return input;
    }
    final directory = await getTemporaryDirectory();
    final outputPath = '${directory.path}/${const Uuid().v4()}.jpg';
    XFile? compressed;
    for (final quality in [82, 72, 62, 52, 42, 32]) {
      compressed = await FlutterImageCompress.compressAndGetFile(
        input.path,
        outputPath,
        quality: quality,
        minWidth: 1280,
        minHeight: 720,
        format: CompressFormat.jpeg,
      );
      if (compressed != null && await compressed.length() < maxBytes) {
        return compressed;
      }
    }
    if (compressed == null || await compressed.length() >= maxBytes) {
      throw Exception(
        'Image could not be compressed below 1 MB. Choose a smaller image.',
      );
    }
    return compressed;
  }

  Future<String> uploadFile({
    required String uid,
    required String path,
    required XFile file,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('The selected image is empty.');
      await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentType(file.name)),
      );
    } else {
      final compressed = await compress(file);
      await ref.putFile(
        File(compressed.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
    }
    return ref.getDownloadURL();
  }

  String _contentType(String name) {
    final extension = name.toLowerCase().split('.').last;
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<String> uploadBytes({
    required String uid,
    required String path,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw Exception('The generated poster image is empty.');
    final ref = FirebaseStorage.instance.ref(path);
    if (kIsWeb) {
      await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      return ref.getDownloadURL();
    }

    Uint8List optimized = bytes;
    var contentType = 'image/png';
    var uploadPath = path;
    if (optimized.length >= maxBytes) {
      for (final width in [820, 720, 640, 560, 480]) {
        optimized = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: width,
          minHeight: (width * 0.68).round(),
          quality: 100,
          format: CompressFormat.png,
        );
        if (optimized.length < maxBytes) break;
      }
    }
    if (optimized.length >= maxBytes) {
      contentType = 'image/jpeg';
      if (uploadPath.endsWith('.png')) {
        uploadPath = '${uploadPath.substring(0, uploadPath.length - 4)}.jpg';
      }
      for (final quality in [82, 72, 62, 52, 42, 32]) {
        optimized = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 900,
          minHeight: 620,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (optimized.length < maxBytes) break;
      }
    }
    if (optimized.length >= maxBytes) {
      throw Exception('Composited image could not be compressed below 1 MB.');
    }
    final uploadRef = FirebaseStorage.instance.ref(uploadPath);
    await uploadRef.putData(
      optimized,
      SettableMetadata(contentType: contentType),
    );
    return uploadRef.getDownloadURL();
  }
}
