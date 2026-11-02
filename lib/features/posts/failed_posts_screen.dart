import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/backend_api_service.dart';
import 'data/post_repository.dart';

class FailedPostsScreen extends StatelessWidget {
  const FailedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PostRepository().watchFailed(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
              child: Text('Unable to load failed posts: ${snapshot.error}'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No failed posts.'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) => _FailedPostCard(post: docs[index]),
        );
      },
    );
  }
}

class _FailedPostCard extends StatefulWidget {
  const _FailedPostCard({required this.post});
  final QueryDocumentSnapshot<Map<String, dynamic>> post;

  @override
  State<_FailedPostCard> createState() => _FailedPostCardState();
}

class _FailedPostCardState extends State<_FailedPostCard> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendApiService().retryPost(widget.post.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.post.data();
    final failure = (data['failureCode'] as String?) ?? 'UNKNOWN_ERROR';
    final caption = (data['aiCaption'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text((data['rawNotes'] as String?) ?? 'Post',
                style: Theme.of(context).textTheme.titleMedium),
            if (caption.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(caption,
                      maxLines: 4, overflow: TextOverflow.ellipsis)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Failure: $failure',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(_busy ? 'Retrying…' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
