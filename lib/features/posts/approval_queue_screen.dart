import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/backend_api_service.dart';
import 'package:flutter/material.dart';

import '../share/local_share_service.dart';
import 'data/post_repository.dart';

class ApprovalQueueScreen extends StatelessWidget {
  const ApprovalQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = PostRepository().watchPendingApproval(uid);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load approval queue: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Center(child: Text(strings.noPendingPosts));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) => _ApprovalCard(post: docs[index]),
        );
      },
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({required this.post});
  final QueryDocumentSnapshot<Map<String, dynamic>> post;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  late final TextEditingController _caption;
  bool _busy = false;
  bool _refreshing = false;
  int _selectedCaption = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _caption = TextEditingController(
      text: (widget.post.data()['aiCaption'] as String?) ?? '',
    );
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _moreOptions() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final captions =
          await BackendApiService().moreCaptionOptions(widget.post.id);
      if (!mounted || captions.isEmpty) return;
      setState(() {
        _selectedCaption = 0;
        _caption.text = captions.first;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not generate more options: $error');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _update(String status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (status == 'rejected') {
        await BackendApiService().rejectPost(widget.post.id);
      } else {
        await BackendApiService().approveAndPublish(
          postId: widget.post.id,
          caption: _caption.text.trim(),
        );
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareToDestination(String destination) async {
    const names = <String, String>{
      'facebook': 'Facebook',
      'instagram': 'Instagram',
      'threads': 'Threads',
      'whatsapp_group': 'WhatsApp Group',
      'whatsapp_channel': 'WhatsApp Channel',
      'other': 'another app',
    };
    final destinationName = names[destination]!;
    final guidance = switch (destination) {
      'whatsapp_group' =>
        'Choose WhatsApp in the share sheet, select the Panchayat group, then tap Send.',
      'whatsapp_channel' =>
        'Choose WhatsApp in the share sheet. Then open your Channel and publish the prepared update.',
      'facebook' =>
        'Choose Facebook in the share sheet. Select the Page or destination and finish the post inside Facebook.',
      'instagram' =>
        'Choose Instagram if it appears. Complete the post inside Instagram; some devices may require saving the image and creating the post there.',
      'threads' =>
        'Choose Threads if it appears. Review the image and caption and publish inside Threads.',
      _ => 'Choose an installed app from the share sheet and finish sharing there.',
    };

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Share to $destinationName'),
        content: Text('$guidance\n\nSarpanch Social Connect will not publish automatically to this destination.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = widget.post.data();
      await LocalShareService().sharePost(
        imageUrl: (data['finalCompositedImage'] as String?) ?? '',
        caption: _caption.text.trim(),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm sharing'),
          content: Text('Did you finish publishing this update to $destinationName inside that app?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes, shared'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await BackendApiService().recordManualShare(
          postId: widget.post.id,
          destination: destination,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$destinationName marked as manually shared.')),
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Manual share failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseManualDestination() async {
    const destinations = <(String, String, IconData)>[
      ('facebook', 'Facebook', Icons.facebook),
      ('instagram', 'Instagram', Icons.camera_alt_outlined),
      ('threads', 'Threads', Icons.alternate_email),
      ('whatsapp_group', 'WhatsApp Group', Icons.groups_outlined),
      ('whatsapp_channel', 'WhatsApp Channel', Icons.campaign_outlined),
      ('other', 'Other installed app', Icons.ios_share_outlined),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose a destination'),
              subtitle: Text('Manual sharing opens your device share sheet. You must finish the post in the selected app.'),
            ),
            ...destinations.map((item) => ListTile(
                  leading: Icon(item.$3),
                  title: Text(item.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheetContext, item.$1),
                )),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _shareToDestination(selected);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final data = widget.post.data();
    final imageUrl = (data['finalCompositedImage'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
              ),
            const SizedBox(height: 12),
            if (data['aiCaptions'] is List &&
                (data['aiCaptions'] as List).isNotEmpty) ...[
              Text('Choose a caption',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: _selectedCaption,
                onChanged: (value) {
                  if (_busy || value == null) return;
                  final captions = data['aiCaptions'] as List;
                  setState(() {
                    _selectedCaption = value;
                    _caption.text = captions[value].toString();
                  });
                },
                child: Column(
                  children: (data['aiCaptions'] as List)
                      .asMap()
                      .entries
                      .map((entry) => Card(
                            child: RadioListTile<int>(
                              value: entry.key,
                              title: Text(entry.value.toString()),
                              subtitle: Text('Option ${entry.key + 1}'),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: (_busy || _refreshing) ? null : _moreOptions,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(_refreshing ? 'Generating…' : 'More options'),
            ),
            TextField(
              controller: _caption,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Edit selected caption',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseManualDestination,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Share manually to a platform'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _update('rejected'),
                    child: Text(strings.reject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _busy ? null : () => _update('approved_to_publish'),
                    icon: const Icon(Icons.publish),
                    label: Text(strings.approve),
                  ),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
