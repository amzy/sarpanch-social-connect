import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LocalShareService {
  Future<void> sharePost({
    required String imageUrl,
    required String caption,
  }) async {
    final bytes = await FirebaseStorage.instance
        .refFromURL(imageUrl)
        .getData(8 * 1024 * 1024);
    if (bytes == null) throw Exception('Unable to download the final image.');
    final hasGalleryAccess = await Gal.hasAccess();
    if (!hasGalleryAccess) await Gal.requestAccess();
    if (!await Gal.hasAccess()) {
      throw Exception('Photo library permission was not granted.');
    }
    await Gal.putImageBytes(bytes, album: 'Sarpanch Social Connect');
    final isPng = bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final extension = isPng ? 'png' : 'jpg';
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/sarpanch-post-${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Clipboard.setData(ClipboardData(text: caption));
    await SharePlus.instance.share(
      ShareParams(
        text: caption,
        files: [XFile(file.path, mimeType: isPng ? 'image/png' : 'image/jpeg')],
        subject: 'Gram Panchayat update',
      ),
    );
  }
}
