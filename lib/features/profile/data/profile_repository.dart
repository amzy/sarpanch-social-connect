import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile(String uid) =>
      _firestore.collection('users').doc(uid).snapshots();

  Future<void> completeProfile({
    required String uid,
    required Map<String, Object?> profile,
  }) async {
    await _firestore.collection('users').doc(uid).update(profile);
  }
}
