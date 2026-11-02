import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_upload_service.dart';
import '../../services/retry_queue_service.dart';
import 'before_after_canvas.dart';
import 'data/post_repository.dart';

class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _notes = TextEditingController();
  final _canvasKey = GlobalKey();
  final _picker = ImagePicker();
  final _uploads = ImageUploadService();
  final _retryQueue = RetryQueueService();
  File? _before;
  File? _after;
  String _type = 'development';
  bool _stacked = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _choose(bool before) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null || !mounted) return;
    final compressed = await _uploads.compress(file);
    setState(() {
      if (before) {
        _before = File(compressed.path);
      } else {
        _after = File(compressed.path);
      }
    });
  }

  Future<Uint8List> _captureCanvas() async {
    if (!mounted) {
      throw Exception('The post editor was closed before preview capture.');
    }
    final profileUrl = (widget.profile['imageUrl'] as String?) ?? '';
    final sealUrl = (widget.profile['sealUrl'] as String?) ?? '';
    if (profileUrl.isNotEmpty) {
      await precacheImage(NetworkImage(profileUrl), context);
      if (!mounted) {
        throw Exception('The post editor was closed before preview capture.');
      }
    }
    if (sealUrl.isNotEmpty) {
      await precacheImage(NetworkImage(sealUrl), context);
      if (!mounted) {
        throw Exception('The post editor was closed before preview capture.');
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('Unable to capture the post canvas.');
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw Exception('Unable to encode the composited image.');
    return data.buffer.asUint8List();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_type == 'development' && (_before == null || _after == null)) {
      setState(
        () => _error =
            'Choose both before and after photos for a development update.',
      );
      return;
    }
    if (_type == 'festival' && _notes.text.trim().isEmpty) {
      setState(() => _error = 'Add the festival name or greeting context.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final postId = const Uuid().v4();
    try {
      String beforeUrl = '';
      String afterUrl = '';
      if (_before != null) {
        beforeUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/posts/$postId-before.jpg',
          file: XFile(_before!.path),
        );
      }
      if (_after != null) {
        afterUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/posts/$postId-after.jpg',
          file: XFile(_after!.path),
        );
      }
      final bytes = await _captureCanvas();
      final imageUrl = await _uploads.uploadBytes(
        uid: user.uid,
        path: 'users/${user.uid}/posts/$postId.png',
        bytes: bytes,
      );
      await PostRepository().createPost({
        'postId': postId,
        'uid': user.uid,
        'type': _type,
        'rawNotes': _notes.text.trim(),
        'beforeImageUrl': beforeUrl,
        'afterImageUrl': afterUrl,
        'finalCompositedImage': imageUrl,
        'status': 'pending_ai',
        'scheduledTime': null,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      await _retryQueue.enqueue({
        'kind': 'post_submission',
        'postId': postId,
        'type': _type,
        'rawNotes': _notes.text.trim(),
        'beforePath': _before?.path,
        'afterPath': _after?.path,
        'error': error.toString(),
      });
      setState(
        () => _error =
            'Could not submit. Your retry record is saved on this device. $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(strings.createPost)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'development',
                label: Text(strings.development),
                icon: const Icon(Icons.construction_outlined),
              ),
              ButtonSegment(
                value: 'festival',
                label: Text(strings.festival),
                icon: const Icon(Icons.celebration_outlined),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            onChanged: (_) => setState(() {}),
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: strings.notes,
              alignLabelWithHint: true,
            ),
          ),
          if (_type == 'development') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _choose(true),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _before == null ? 'Select BEFORE photo' : 'Change BEFORE photo',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _choose(false),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _after == null ? 'Select AFTER photo' : 'Change AFTER photo',
              ),
            ),
            SwitchListTile(
              title: const Text('Stack photos vertically'),
              value: _stacked,
              onChanged: (value) => setState(() => _stacked = value),
            ),
          ],
          const SizedBox(height: 16),
          Text('Preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              child: RepaintBoundary(
                key: _canvasKey,
                child: BeforeAfterCanvas(
                  beforeFile: _before,
                  afterFile: _after,
                  sarpanchName:
                      (widget.profile['sarpanchName'] as String?) ?? '',
                  panchayatName:
                      (widget.profile['panchayatName'] as String?) ?? '',
                  profileImageUrl:
                      (widget.profile['imageUrl'] as String?) ?? '',
                  sealUrl: (widget.profile['sealUrl'] as String?) ?? '',
                  notes: _notes.text,
                  stacked: _stacked,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.auto_awesome),
            label: _saving
                ? const Text('Preparing…')
                : const Text('Generate caption for approval'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}
