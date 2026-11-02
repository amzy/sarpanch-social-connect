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
import '../../services/backend_api_service.dart';
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
  late String _contentLanguage;
  bool _stacked = false;
  String _frameStyle = 'classic';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final configured = widget.profile['primaryLanguage'] as String?;
    _contentLanguage =
        supportedContentLanguages.contains(configured) ? configured! : 'Hindi';
  }

  static const supportedContentLanguages = [
    'English',
    'Hindi',
    'Marathi',
    'Telugu',
    'Tamil',
    'Gujarati',
  ];

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

  Future<void> _suggestFrame() async {
    if (_notes.text.trim().isEmpty) {
      setState(() =>
          _error = 'Add post details before asking AI to suggest a frame.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final suggestion = await BackendApiService().suggestPostFrame(
        postType: _type,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      setState(() => _frameStyle = suggestion);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not suggest a frame: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_notes.text.trim().isEmpty) {
      setState(
          () => _error = 'Describe the update before generating captions.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final postId = const Uuid().v4();
    var postCreated = false;
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
      var imageUrl = '';
      if (_before != null || _after != null) {
        final bytes = await _captureCanvas();
        imageUrl = await _uploads.uploadBytes(
          uid: user.uid,
          path: 'users/${user.uid}/posts/$postId.png',
          bytes: bytes,
        );
      }
      await PostRepository().createPost({
        'postId': postId,
        'uid': user.uid,
        'type': _type,
        'contentLanguage': _contentLanguage,
        'rawNotes': _notes.text.trim(),
        'beforeImageUrl': beforeUrl,
        'afterImageUrl': afterUrl,
        'finalCompositedImage': imageUrl,
        'status': 'pending_ai',
        'scheduledTime': null,
      });
      postCreated = true;
      try {
        await BackendApiService().generatePost(postId);
      } catch (_) {
        await BackendApiService().retryPost(postId);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!postCreated) {
        await _retryQueue.enqueue({
          'kind': 'post_submission',
          'postId': postId,
          'type': _type,
          'rawNotes': _notes.text.trim(),
          'beforePath': _before?.path,
          'afterPath': _after?.path,
          'error': error.toString(),
        });
      }
      setState(
        () => _error = postCreated
            ? 'Your post is saved, but caption generation could not be confirmed. Check the Failed tab or retry shortly. $error'
            : 'Could not submit. Your retry record is saved on this device. $error',
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
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Post type'),
            items: const [
              DropdownMenuItem(
                  value: 'development', child: Text('Development update')),
              DropdownMenuItem(
                  value: 'festival', child: Text('Festival / greeting')),
              DropdownMenuItem(
                  value: 'announcement', child: Text('Public announcement')),
              DropdownMenuItem(value: 'project', child: Text('Project update')),
              DropdownMenuItem(value: 'event', child: Text('Community event')),
              DropdownMenuItem(
                  value: 'public_service', child: Text('Public service')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _contentLanguage,
            decoration:
                const InputDecoration(labelText: 'Post content language'),
            items: supportedContentLanguages
                .map((language) => DropdownMenuItem(
                      value: language,
                      child: Text(language),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _contentLanguage = value);
            },
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
          const SizedBox(height: 14),
          Text('Choose poster frame', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Classic'),
                selected: _frameStyle == 'classic',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'classic'),
              ),
              ChoiceChip(
                label: const Text('Celebration'),
                selected: _frameStyle == 'celebration',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'celebration'),
              ),
              ChoiceChip(
                label: const Text('Development'),
                selected: _frameStyle == 'development',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'development'),
              ),
              ChoiceChip(
                label: const Text('Announcement'),
                selected: _frameStyle == 'announcement',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'announcement'),
              ),
              ChoiceChip(
                label: const Text('Minimal'),
                selected: _frameStyle == 'minimal',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'minimal'),
              ),
              ChoiceChip(
                label: const Text('India tricolour'),
                selected: _frameStyle == 'tricolor',
                onSelected: _saving ? null : (_) => setState(() => _frameStyle = 'tricolor'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Selected: ${_frameStyle == 'tricolor' ? 'India tricolour' : _frameStyle[0].toUpperCase() + _frameStyle.substring(1)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          OutlinedButton.icon(
          OutlinedButton.icon(
            onPressed: _saving ? null : _suggestFrame,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Suggest frame with AI'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _choose(true),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_before == null
                ? 'Add BEFORE photo (optional)'
                : 'Change BEFORE photo'),
          ),
          if (_before != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _before = null),
                child: const Text('Remove before photo'),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _choose(false),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_after == null
                ? 'Add AFTER photo (optional)'
                : 'Change AFTER photo'),
          ),
          if (_after != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _after = null),
                child: const Text('Remove after photo'),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stack photos vertically'),
            value: _stacked,
            onChanged: (_before == null && _after == null)
                ? null
                : (value) => setState(() => _stacked = value),
          ),
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
                  sarpanchNameHindi:
                      (widget.profile['sarpanchNameHindi'] as String?) ?? '',
                  panchayatNameHindi:
                      (widget.profile['panchayatNameHindi'] as String?) ?? '',
                  profileImageUrl:
                      (widget.profile['imageUrl'] as String?) ?? '',
                  sealUrl: (widget.profile['sealUrl'] as String?) ?? '',
                  notes: _notes.text,
                  stacked: _stacked,
                  frameStyle: _frameStyle,
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
