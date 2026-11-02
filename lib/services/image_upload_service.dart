import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImageUploadService {
  static const int maxBytes = 1024 * 1024;

  Future<XFile> compress(XFile input) async {
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
      if (compressed != null && await compressed.length() < maxBytes)
        return compressed;
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
    final compressed = await compress(file);
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(
      File(compressed.path),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  Future<String> uploadBytes({
    required String uid,
    required String path,
    required Uint8List bytes,
  }) async {
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
      if (uploadPath.endsWith('.png'))
        uploadPath = '${uploadPath.substring(0, uploadPath.length - 4)}.jpg';
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
    if (optimized.length >= maxBytes)
      throw Exception('Composited image could not be compressed below 1 MB.');
    final ref = FirebaseStorage.instance.ref(uploadPath);
    await ref.putData(optimized, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
