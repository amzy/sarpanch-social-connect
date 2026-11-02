import 'package:cloud_firestore/cloud_firestore.dart';

class PostRepository {
  PostRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingApproval(
    String uid,
  ) => _firestore
      .collection('posts_queue')
      .where('uid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending_approval')
      .orderBy('creationTimestamp', descending: true)
      .snapshots();

  Future<void> createPost(Map<String, Object?> post) async {
    final postId = post['postId'] as String;
    await _firestore.collection('posts_queue').doc(postId).set({
      ...post,
      'creationTimestamp':
          post['creationTimestamp'] ?? FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCaption(String postId, String caption) => _firestore
      .collection('posts_queue')
      .doc(postId)
      .update({'aiCaption': caption});

  Future<void> approve(String postId, String caption) => _firestore
      .collection('posts_queue')
      .doc(postId)
      .update({'status': 'approved_to_publish', 'aiCaption': caption});

  Future<void> reject(String postId) => _firestore
      .collection('posts_queue')
      .doc(postId)
      .update({'status': 'rejected'});
}
