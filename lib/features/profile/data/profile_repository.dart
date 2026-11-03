import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileRepository {
  ProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile(String uid) =>
      _firestore.collection('users').doc(uid).snapshots();

  Future<void> completeProfile({
    required String uid,
    required Map<String, Object?> profile,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('You must be signed in to save this profile.');
    }

    final ref = _firestore.collection('users').doc(uid);
    final existing = await ref.get();
    if (existing.exists) {
      // Update only profile-owned fields. Do not rewrite registration metadata,
      // billing state, creation timestamps, or server-managed usage counters.
      await ref.update(profile);
      return;
    }

    final email = user.email ?? '';
    final username = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim().toLowerCase()
        : (email.contains('@') ? email.split('@').first : uid);
    await ref.set({
      'uid': uid,
      'email': email,
      'username': username,
      'mobileNumber': user.phoneNumber ?? '',
      'profileComplete': true,
      'plan': 'free',
      'billingStatus': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      ...profile,
    });
  }
}
