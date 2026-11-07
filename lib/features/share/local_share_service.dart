import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Prepares post media from any public HTTPS media host and opens the native
/// platform share sheet. Returning from the sheet is not proof of delivery.
class LocalShareService {
  Future<void> sharePost({
    required String imageUrl,
    required String caption,
  }) async {
    final text = caption.trim();
    if (text.isEmpty) throw ArgumentError('A caption is required to share.');

    if (imageUrl.trim().isEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Gram Panchayat update'),
      );
      return;
    }

    final uri = Uri.tryParse(imageUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('The post image must use a valid HTTPS URL.');
    }
    final result = await http.get(uri).timeout(const Duration(seconds: 30));
    if (result.statusCode != 200 || result.bodyBytes.isEmpty) {
      throw Exception('Unable to download the final post image (HTTP ${result.statusCode}).');
    }
    if (result.bodyBytes.length > 8 * 1024 * 1024) {
      throw Exception('The post image exceeds the 8 MB sharing limit.');
    }

    final bytes = result.bodyBytes;
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
    await Clipboard.setData(ClipboardData(text: text));
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [XFile(file.path, mimeType: isPng ? 'image/png' : 'image/jpeg')],
        subject: 'Gram Panchayat update',
      ),
    );
  }
}
