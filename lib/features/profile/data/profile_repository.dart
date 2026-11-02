import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile(String uid) =>
      _firestore.collection('users').doc(uid).snapshots();

  Future<void> createProfile(Map<String, Object?> profile) async {
    final uid = profile['uid'] as String;
    await _firestore.collection('users').doc(uid).set({
      ...profile,
      'createdAt': profile['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
