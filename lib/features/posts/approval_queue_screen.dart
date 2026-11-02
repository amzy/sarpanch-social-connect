import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../share/local_share_service.dart';
import 'data/post_repository.dart';

class ApprovalQueueScreen extends StatelessWidget {
  const ApprovalQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = PostRepository().watchPendingApproval(uid);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load approval queue: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _caption = TextEditingController(text: (widget.post.data()['aiCaption'] as String?) ?? '');
  }

  @override
  void dispose() { _caption.dispose(); super.dispose(); }

  Future<void> _update(String status) async {
    setState(() { _busy = true; _error = null; });
    try {
      final repository = PostRepository();
      if (status == 'rejected') {
        await repository.reject(widget.post.id);
      } else {
        await repository.approve(widget.post.id, _caption.text.trim());
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final data = widget.post.data();
    try {
      await LocalShareService().sharePost(
        imageUrl: (data['finalCompositedImage'] as String?) ?? '',
        caption: _caption.text.trim(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Share failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final data = widget.post.data();
    final imageUrl = String(data['finalCompositedImage'] ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (imageUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(imageUrl, fit: BoxFit.contain, loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())))),
        const SizedBox(height: 12),
        TextField(controller: _caption, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: strings.caption, alignLabelWithHint: true)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _busy ? null : _share, icon: const Icon(Icons.share_outlined), label: Text(strings.share)),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _update('rejected'), child: Text(strings.reject))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _update('approved_to_publish'), icon: const Icon(Icons.publish), label: Text(strings.approve))),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
    );
  }
}
