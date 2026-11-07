import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_upload_service.dart';
import '../../services/local_prompt_compiler.dart';
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
  static const _promptCompiler = LocalPromptCompiler();
  bool _uploadExistingPost = false;
  XFile? _uploadedPost;
  Uint8List? _uploadedPostBytes;
  XFile? _before;
  XFile? _after;
  Uint8List? _beforeBytes;
  Uint8List? _afterBytes;
  String _type = 'development';
  late String _contentLanguage;
  bool _stacked = false;
  String _frameStyle = 'classic';
  bool _saving = false;
  String? _error;
  String _generatedArtworkUrl = '';
  Map<String, dynamic> _localizedProfile = const {};

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

  Future<void> _chooseExistingPostFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final selected = result.files.single;
      final bytes = selected.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Unable to read the selected image file.');
      }
      if (bytes.length > ImageUploadService.maxBytes) {
        throw Exception('Choose an image smaller than 8 MB.');
      }
      final file = XFile.fromData(
        bytes,
        name: selected.name,
        mimeType: selected.extension?.toLowerCase() == 'png'
            ? 'image/png'
            : selected.extension?.toLowerCase() == 'webp'
                ? 'image/webp'
                : 'image/jpeg',
      );
      setState(() {
        _uploadedPost = file;
        _uploadedPostBytes = bytes;
        _error = null;
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Could not select the post file: $error');
    }
  }

  Future<void> _chooseExistingPostFromDevice(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('The selected photo is empty.');
      if (bytes.length > ImageUploadService.maxBytes) {
        throw Exception('Choose a photo smaller than 8 MB.');
      }
      setState(() {
        _uploadedPost = file;
        _uploadedPostBytes = bytes;
        _error = null;
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Could not select the photo: $error');
    }
  }

  Future<void> _submitExistingPost() async {
    final user = FirebaseAuth.instance.currentUser;
    final file = _uploadedPost;
    if (user == null) return;
    if (file == null || _uploadedPostBytes == null) {
      setState(() => _error = 'Choose an existing post image first.');
      return;
    }
    if (_notes.text.trim().isEmpty) {
      setState(() =>
          _error = 'Add a caption or describe this post before continuing.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final postId = const Uuid().v4();
    var postCreated = false;
    try {
      final imageUrl = await _uploads.uploadFile(
        uid: user.uid,
        path:
            'users/${user.uid}/posts/$postId-uploaded.${file.name.split('.').last}',
        file: file,
      );
      await PostRepository().createPost({
        'postId': postId,
        'uid': user.uid,
        'type': _type,
        'contentLanguage': _contentLanguage,
        'rawNotes': _notes.text.trim(),
        'promptNotes': _promptCompiler.compile(_notes.text),
        'beforeImageUrl': '',
        'afterImageUrl': '',
        'finalCompositedImage': imageUrl,
        'source': 'user_uploaded',
        'status': 'pending_ai',
        'scheduledTime': null,
      });
      postCreated = true;
      try {
        await BackendApiService().generatePost(postId);
      } catch (generationError) {
        try {
          await PostRepository()
              .markGenerationFailed(postId, generationError.toString());
        } catch (_) {}
        rethrow;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!postCreated) {
        await _retryQueue.enqueue({
          'kind': 'post_submission',
          'postId': postId,
          'type': _type,
          'rawNotes': _notes.text.trim(),
          'promptNotes': _promptCompiler.compile(_notes.text),
          'source': 'user_uploaded',
          'error': error.toString(),
        });
      }
      if (mounted) {
        setState(() => _error = postCreated
            ? 'Your uploaded post was saved, but caption generation failed. Open the Failed tab to retry. $error'
            : 'Could not submit your uploaded post. A retry record was saved on this device. $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !mounted) return;
    setState(() {
      if (before) {
        _before = file;
        _beforeBytes = bytes;
      } else {
        _after = file;
        _afterBytes = bytes;
      }
    });
  }

  Future<Uint8List> _captureCanvas() async {
    if (!mounted) {
      throw Exception('The post editor was closed before preview capture.');
    }
    final profileUrl = (widget.profile['imageUrl'] as String?) ?? '';
    final sealUrl = (widget.profile['sealUrl'] as String?) ?? '';
    if (_generatedArtworkUrl.isNotEmpty) {
      await precacheImage(NetworkImage(_generatedArtworkUrl), context);
      if (!mounted) {
        throw Exception('The post editor was closed before preview capture.');
      }
    }
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
        notes: _promptCompiler.compile(_notes.text),
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
    var promptNotes = '';
    try {
      promptNotes = _promptCompiler.compile(_notes.text);
      // Generate the artwork from the content prompt. The Worker loads the saved
      // Panchayat profile; the original profile photo is composited unchanged.
      final artwork = await BackendApiService().generatePostArtwork(
        postType: _type,
        notes: promptNotes,
        contentLanguage: _contentLanguage,
      );
      _generatedArtworkUrl = artwork['imageUrl'] as String;
      _localizedProfile = Map<String, dynamic>.from(
        artwork['localizedProfile'] as Map? ?? const {},
      );
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      String beforeUrl = '';
      String afterUrl = '';
      if (_before != null) {
        beforeUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/posts/$postId-before.jpg',
          file: _before!,
        );
      }
      if (_after != null) {
        afterUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/posts/$postId-after.jpg',
          file: _after!,
        );
      }
      // Every post must have a finished visual, even when no source photos are supplied.
      // Ask Gemini to select a suitable frame unless the user has already chosen one.
      if (_frameStyle == 'classic') {
        try {
          _frameStyle = await BackendApiService().suggestPostFrame(
            postType: _type,
            notes: promptNotes,
          );
        } catch (_) {
          // Keep the safe Classic template when AI frame suggestion is unavailable.
        }
      }
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      final posterBytes = await _captureCanvas();
      final imageUrl = await _uploads.uploadBytes(
        uid: user.uid,
        path: 'users/${user.uid}/posts/$postId.png',
        bytes: posterBytes,
      );
      await PostRepository().createPost({
        'postId': postId,
        'uid': user.uid,
        'type': _type,
        'contentLanguage': _contentLanguage,
        'rawNotes': _notes.text.trim(),
        'promptNotes': promptNotes,
        'beforeImageUrl': beforeUrl,
        'afterImageUrl': afterUrl,
        'finalCompositedImage': imageUrl,
        'status': 'pending_ai',
        'scheduledTime': null,
      });
      postCreated = true;
      try {
        await BackendApiService().generatePost(postId);
      } catch (generationError) {
        // The Worker owns the generation lifecycle and normally marks the post
        // failed itself. A client-side update can be denied after the Worker has
        // already moved the status to processing_ai/failed; never let that
        // secondary Firestore error hide the original backend/Gemini error.
        try {
          await PostRepository().markGenerationFailed(
            postId,
            generationError.toString(),
          );
        } catch (_) {
          // Preserve the generation error. The Worker may already have saved
          // the authoritative failureCode/failureMessage on the post.
        }
        rethrow;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!postCreated) {
        await _retryQueue.enqueue({
          'kind': 'post_submission',
          'postId': postId,
          'type': _type,
          'rawNotes': _notes.text.trim(),
          'promptNotes': promptNotes,
          'error': error.toString(),
        });
      }
      setState(
        () => _error = postCreated
            ? 'Your post was saved to Failed because caption generation could not be completed. Open the Failed tab to retry. $error'
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.auto_awesome),
                label: Text('Create new post'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.upload_file_outlined),
                label: Text('Upload existing post'),
              ),
            ],
            selected: {_uploadExistingPost},
            onSelectionChanged: _saving
                ? null
                : (selection) => setState(() {
                      _uploadExistingPost = selection.first;
                      _error = null;
                    }),
          ),
          const SizedBox(height: 16),
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
          if (_uploadExistingPost) ...[
            Text('Upload your ready-made post',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Use a poster image from Files, choose a photo from your device, or take a new photo. Add the caption or post details below.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_uploadedPostBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  _uploadedPostBytes!,
                  height: 280,
                  fit: BoxFit.contain,
                ),
              )
            else
              Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 42),
                      SizedBox(height: 8),
                      Text('No post image selected'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _chooseExistingPostFromFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose image from Files'),
            ),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _chooseExistingPostFromDevice(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose photo from device'),
            ),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _chooseExistingPostFromDevice(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
            if (_uploadedPost != null)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _uploadedPost = null;
                          _uploadedPostBytes = null;
                        }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove selected image'),
              ),
          ] else ...[
            Text('Choose poster frame',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Classic'),
                  selected: _frameStyle == 'classic',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'classic'),
                ),
                ChoiceChip(
                  label: const Text('Celebration'),
                  selected: _frameStyle == 'celebration',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'celebration'),
                ),
                ChoiceChip(
                  label: const Text('Development'),
                  selected: _frameStyle == 'development',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'development'),
                ),
                ChoiceChip(
                  label: const Text('Announcement'),
                  selected: _frameStyle == 'announcement',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'announcement'),
                ),
                ChoiceChip(
                  label: const Text('Minimal'),
                  selected: _frameStyle == 'minimal',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'minimal'),
                ),
                ChoiceChip(
                  label: const Text('India tricolour'),
                  selected: _frameStyle == 'tricolor',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frameStyle = 'tricolor'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Selected: ${_frameStyle == 'tricolor' ? 'India tricolour' : _frameStyle[0].toUpperCase() + _frameStyle.substring(1)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
                  onPressed: () => setState(() {
                    _before = null;
                    _beforeBytes = null;
                  }),
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
                  onPressed: () => setState(() {
                    _after = null;
                    _afterBytes = null;
                  }),
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
                    beforeBytes: _beforeBytes,
                    afterBytes: _afterBytes,
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
                    generatedArtworkUrl: _generatedArtworkUrl,
                    localizedSarpanchName:
                        (_localizedProfile['sarpanchName'] as String?) ?? '',
                    localizedPanchayatName:
                        (_localizedProfile['panchayatName'] as String?) ?? '',
                    localizedDistrict:
                        (_localizedProfile['district'] as String?) ?? '',
                    localizedState:
                        (_localizedProfile['state'] as String?) ?? '',
                    contentLanguage: _contentLanguage,
                  ),
                ),
              ),
            ),
          ],
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
            onPressed: _saving
                ? null
                : (_uploadExistingPost ? _submitExistingPost : _submit),
            icon: Icon(_uploadExistingPost
                ? Icons.upload_file_outlined
                : Icons.auto_awesome),
            label: _saving
                ? const Text('Preparing…')
                : Text(_uploadExistingPost
                    ? 'Upload post for caption approval'
                    : 'Generate caption for approval'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}
